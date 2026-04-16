const std = @import("std");

const Config = struct {
    root: []const u8,
    port: u16,
    host: []const u8,
};

const Entry = struct {
    name: []const u8,
    type: []const u8,
    size: u64,
    modified: i64,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // Separate arena for config — freed cleanly on exit
    var config_arena = std.heap.ArenaAllocator.init(alloc);
    defer config_arena.deinit();
    const ca = config_arena.allocator();

    var args_iter = try std.process.ArgIterator.initWithAllocator(ca);
    defer args_iter.deinit();
    _ = args_iter.next(); // skip executable name

    var config = Config{
        .root = try std.fs.realpathAlloc(ca, "."),
        .port = 8080,
        .host = "0.0.0.0",
    };

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--root")) {
            const val = args_iter.next() orelse continue;
            config.root = std.fs.realpathAlloc(ca, val) catch |err| {
                std.debug.print("error: --root path not found: {s} ({s})\n", .{ val, @errorName(err) });
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--port")) {
            const val = args_iter.next() orelse continue;
            config.port = std.fmt.parseInt(u16, val, 10) catch {
                std.debug.print("error: invalid --port value: {s}\n", .{val});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--host")) {
            config.host = try ca.dupe(u8, args_iter.next() orelse continue);
        }
    }

    const address = try std.net.Address.parseIp(config.host, config.port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("dirz listening on {s}:{d}  root={s}\n", .{ config.host, config.port, config.root });

    while (true) {
        const conn = server.accept() catch |err| {
            std.debug.print("accept error: {}\n", .{err});
            continue;
        };
        const ctx = alloc.create(ConnCtx) catch |err| {
            std.debug.print("alloc error: {}\n", .{err});
            conn.stream.close();
            continue;
        };
        ctx.* = .{ .conn = conn, .config = config, .gpa = alloc };
        const thread = std.Thread.spawn(.{}, handleConn, .{ctx}) catch |err| {
            std.debug.print("spawn error: {}\n", .{err});
            conn.stream.close();
            alloc.destroy(ctx);
            continue;
        };
        thread.detach();
    }
}

const ConnCtx = struct {
    conn: std.net.Server.Connection,
    config: Config,
    gpa: std.mem.Allocator,
};

fn handleConn(ctx: *ConnCtx) void {
    const stream = ctx.conn.stream;
    const config = ctx.config;
    const gpa = ctx.gpa;
    defer {
        stream.close();
        gpa.destroy(ctx);
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    handleRequest(stream, config, allocator) catch |err| {
        std.debug.print("request error: {}\n", .{err});
        writeError(stream, 500, "internal", allocator) catch {};
    };
}

fn handleRequest(stream: std.net.Stream, config: Config, allocator: std.mem.Allocator) !void {
    var buf: [8192]u8 = undefined;
    const n = stream.read(&buf) catch return;
    if (n == 0) return;

    const request = buf[0..n];
    const line_end = std.mem.indexOf(u8, request, "\r\n") orelse request.len;
    const request_line = request[0..line_end];

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return;
    const raw_path = parts.next() orelse "/";

    if (!std.mem.eql(u8, method, "GET")) {
        try writeError(stream, 405, "method not allowed", allocator);
        return;
    }

    const q_idx = std.mem.indexOf(u8, raw_path, "?");
    const path = if (q_idx) |qi| raw_path[0..qi] else raw_path;
    const query = if (q_idx) |qi| raw_path[qi + 1 ..] else "";

    if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "")) {
        try serveIndex(stream, allocator);
    } else if (std.mem.startsWith(u8, path, "/api/ls")) {
        try serveApiLs(stream, config, allocator, query);
    } else if (std.mem.startsWith(u8, path, "/files")) {
        const file_path = if (path.len > 6) path[6..] else "";
        try serveStaticFile(stream, config, allocator, file_path);
    } else {
        try writeError(stream, 404, "not found", allocator);
    }
}

fn serveIndex(stream: std.net.Stream, allocator: std.mem.Allocator) !void {
    _ = allocator;
    const html = @embedFile("index.html");
    try writeResponse(stream, 200, "text/html; charset=utf-8", html);
}

fn serveApiLs(stream: std.net.Stream, config: Config, allocator: std.mem.Allocator, query: []const u8) !void {
    var req_path: []const u8 = "/";
    var qparts = std.mem.splitScalar(u8, query, '&');
    while (qparts.next()) |kv| {
        if (std.mem.startsWith(u8, kv, "path=")) {
            req_path = try urlDecode(allocator, kv[5..]);
        }
    }
    if (req_path.len == 0) req_path = "/";

    const abs_path = try buildAbsPath(allocator, config.root, req_path);

    const resolved = std.fs.realpathAlloc(allocator, abs_path) catch {
        try writeError(stream, 404, "not found", allocator);
        return;
    };
    if (!std.mem.startsWith(u8, resolved, config.root)) {
        try writeError(stream, 403, "forbidden", allocator);
        return;
    }

    var dir = std.fs.openDirAbsolute(resolved, .{ .iterate = true }) catch {
        try writeError(stream, 404, "not found", allocator);
        return;
    };
    defer dir.close();

    var entries = std.array_list.Managed(Entry).init(allocator);

    var iter = dir.iterate();
    while (try iter.next()) |de| {
        const stat = dir.statFile(de.name) catch continue;
        const etype: []const u8 = if (de.kind == .directory) "dir" else "file";
        try entries.append(.{
            .name = try allocator.dupe(u8, de.name),
            .type = etype,
            .size = stat.size,
            .modified = @intCast(@divFloor(stat.mtime, std.time.ns_per_s)),
        });
    }

    const body = try std.json.Stringify.valueAlloc(allocator, .{ .path = req_path, .entries = entries.items }, .{});

    try writeResponse(stream, 200, "application/json", body);
}

fn serveStaticFile(stream: std.net.Stream, config: Config, allocator: std.mem.Allocator, file_path: []const u8) !void {
    const decoded = try urlDecode(allocator, file_path);
    const abs_path = try buildAbsPath(allocator, config.root, decoded);

    const resolved = std.fs.realpathAlloc(allocator, abs_path) catch {
        try writeError(stream, 404, "not found", allocator);
        return;
    };
    if (!std.mem.startsWith(u8, resolved, config.root)) {
        try writeError(stream, 403, "forbidden", allocator);
        return;
    }

    const file = std.fs.openFileAbsolute(resolved, .{}) catch {
        try writeError(stream, 404, "not found", allocator);
        return;
    };
    defer file.close();

    const stat = try file.stat();
    const mime = guessMime(resolved);

    var hdr = std.array_list.Managed(u8).init(allocator);
    const hw = hdr.writer();
    try hw.print("HTTP/1.1 200 OK\r\n", .{});
    try hw.print("Content-Type: {s}\r\n", .{mime});
    try hw.print("Content-Length: {d}\r\n", .{stat.size});
    try hw.print("Content-Disposition: attachment\r\n", .{});
    try hw.print("Connection: close\r\n", .{});
    try hw.print("\r\n", .{});
    try stream.writeAll(hdr.items);

    var fbuf: [8192]u8 = undefined;
    while (true) {
        const nr = try file.read(&fbuf);
        if (nr == 0) break;
        try stream.writeAll(fbuf[0..nr]);
    }
}

fn buildAbsPath(allocator: std.mem.Allocator, root: []const u8, req_path: []const u8) ![]u8 {
    if (req_path.len == 0 or std.mem.eql(u8, req_path, "/")) {
        return allocator.dupe(u8, root);
    }
    const rel = if (req_path[0] == '/') req_path[1..] else req_path;
    if (rel.len == 0) return allocator.dupe(u8, root);
    return std.fs.path.join(allocator, &.{ root, rel });
}

fn writeResponse(stream: std.net.Stream, status: u16, content_type: []const u8, body: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "OK",
    };
    // Use a fixed-size stack buffer for headers, then writeAll
    var hdr_buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&hdr_buf);
    const w = fbs.writer();
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ status, status_text });
    try w.print("Content-Type: {s}\r\n", .{content_type});
    try w.print("Content-Length: {d}\r\n", .{body.len});
    try w.print("Access-Control-Allow-Origin: *\r\n", .{});
    try w.print("Connection: close\r\n", .{});
    try w.print("\r\n", .{});
    try stream.writeAll(fbs.getWritten());
    try stream.writeAll(body);
}

fn writeError(stream: std.net.Stream, status: u16, msg: []const u8, allocator: std.mem.Allocator) !void {
    _ = allocator;
    var body_buf: [128]u8 = undefined;
    const body = try std.fmt.bufPrint(&body_buf, "{{\"error\":\"{s}\"}}", .{msg});
    try writeResponse(stream, status, "application/json", body);
}

fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const byte = std.fmt.parseInt(u8, input[i + 1 .. i + 3], 16) catch {
                try out.append(input[i]);
                i += 1;
                continue;
            };
            try out.append(byte);
            i += 3;
        } else if (input[i] == '+') {
            try out.append(' ');
            i += 1;
        } else {
            try out.append(input[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

fn guessMime(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".pdf")) return "application/pdf";
    if (std.mem.endsWith(u8, path, ".zip")) return "application/zip";
    if (std.mem.endsWith(u8, path, ".txt") or std.mem.endsWith(u8, path, ".md")) return "text/plain";
    return "application/octet-stream";
}
