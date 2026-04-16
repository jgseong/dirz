# Skills.md — Implementation Patterns & Reference

## 1. Zig HTTP Server (std only)

```zig
const std = @import("std");
const net = std.net;
const http = std.http;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const address = try net.Address.parseIp("0.0.0.0", 8080);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const conn = try server.accept();
        const thread = try std.Thread.spawn(.{}, handleConn, .{ conn, allocator });
        thread.detach();
    }
}
```

**Key patterns:**
- Use `std.Thread.spawn` + `detach` for concurrent connections
- `std.heap.ArenaAllocator` per request — free all at end of request
- Read request line manually: `conn.stream.reader().readUntilDelimiterAlloc`

---

## 2. JSON Response (std.json)

```zig
const payload = .{
    .path = current_path,
    .entries = entries.items,
};
var buf = std.ArrayList(u8).init(allocator);
defer buf.deinit();
try std.json.stringify(payload, .{}, buf.writer());
// write buf.items as HTTP response body
```

**Entry struct:**
```zig
const Entry = struct {
    name: []const u8,
    type: []const u8,   // "file" | "dir"
    size: u64,
    modified: i64,      // unix timestamp
};
```

---

## 3. Directory Listing (std.fs)

```zig
var dir = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });
defer dir.close();

var iter = dir.iterate();
while (try iter.next()) |entry| {
    const stat = try dir.statFile(entry.name);
    // entry.kind == .directory | .file
    // stat.size, stat.mtime
}
```

**Safety:** always resolve and validate that the requested path stays within the configured root to prevent path traversal.

```zig
// Validate: resolved path must start with root
const resolved = try std.fs.realpathAlloc(allocator, requested);
if (!std.mem.startsWith(u8, resolved, config.root)) return error.Forbidden;
```

---

## 4. HTTP Response Helpers

```zig
fn writeResponse(
    stream: std.net.Stream,
    status: u16,
    content_type: []const u8,
    body: []const u8,
) !void {
    var writer = stream.writer();
    try writer.print("HTTP/1.1 {d} OK\r\n", .{status});
    try writer.print("Content-Type: {s}\r\n", .{content_type});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.print("Access-Control-Allow-Origin: *\r\n", .{});
    try writer.print("\r\n", .{});
    try writer.writeAll(body);
}
```

---

## 5. Serving Static Files (file download)

```zig
fn serveFile(stream: std.net.Stream, abs_path: []const u8, allocator: std.mem.Allocator) !void {
    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();
    const stat = try file.stat();

    const mime = guessMime(abs_path);
    // write headers manually with Content-Length = stat.size
    // then sendfile-style loop:
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        try stream.writer().writeAll(buf[0..n]);
    }
}
```

---

## 6. URL Parsing

```zig
// Parse path and query string from raw request line
// "GET /api/ls?path=%2Fdocs HTTP/1.1"
fn parsePath(request_line: []const u8) struct { path: []const u8, query: []const u8 } {
    // split on space, take [1], then split on '?' 
}

fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // handle %XX encoding and + as space
}
```

---

## 7. Vue 3 SPA Pattern (single file, CDN)

```html
<!DOCTYPE html>
<html>
<head>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5/dist/css/bootstrap.min.css">
  <style>
    :root { --bs-border-radius: 0; --bs-border-radius-sm: 0; --bs-border-radius-lg: 0; }
    body { font-size: 0.875rem; }
    .table > :not(caption) > * > * { padding: 0.2rem 0.5rem; }
    .navbar { padding: 0.3rem 1rem; min-height: unset; }
    .clickable { cursor: pointer; }
    .sort-icon { opacity: 0.4; font-size: 0.75rem; }
    .sort-icon.active { opacity: 1; }
  </style>
</head>
<body>
  <div id="app"></div>
  <script src="https://cdn.jsdelivr.net/npm/vue@3/dist/vue.esm-browser.prod.js" type="module">
  </script>
  <script type="module">
    import { createApp, ref, computed, onMounted } from 'https://cdn.jsdelivr.net/npm/vue@3/dist/vue.esm-browser.prod.js';
    // app code here
  </script>
</body>
</html>
```

---

## 8. Vue 3 Composition API — File Browser Logic

```javascript
const currentPath = ref('/')
const entries = ref([])
const search = ref('')
const sortKey = ref('name')       // 'name' | 'size' | 'modified'
const sortDir = ref('asc')        // 'asc' | 'desc'

async function loadPath(path) {
  const res = await fetch(`/api/ls?path=${encodeURIComponent(path)}`)
  const data = await res.json()
  currentPath.value = data.path
  entries.value = data.entries
}

const filtered = computed(() => {
  let list = entries.value
  if (search.value) {
    list = list.filter(e => e.name.toLowerCase().includes(search.value.toLowerCase()))
  }
  list = [...list].sort((a, b) => {
    // dirs first, then sort by key
    if (a.type !== b.type) return a.type === 'dir' ? -1 : 1
    let va = a[sortKey.value], vb = b[sortKey.value]
    if (typeof va === 'string') va = va.toLowerCase()
    if (typeof vb === 'string') vb = vb.toLowerCase()
    const cmp = va < vb ? -1 : va > vb ? 1 : 0
    return sortDir.value === 'asc' ? cmp : -cmp
  })
  return list
})

function toggleSort(key) {
  if (sortKey.value === key) sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  else { sortKey.value = key; sortDir.value = 'asc' }
}

function navigate(entry) {
  if (entry.type === 'dir') loadPath(currentPath.value.replace(/\/$/, '') + '/' + entry.name)
  else window.open(`/files${currentPath.value}/${entry.name}`)
}

// Breadcrumb
const breadcrumbs = computed(() => {
  const parts = currentPath.value.split('/').filter(Boolean)
  return [{ label: '/', path: '/' }, ...parts.map((p, i) => ({
    label: p,
    path: '/' + parts.slice(0, i + 1).join('/')
  }))]
})
```

---

## 9. Bootstrap UI Structure

```
[Navbar]  — project name, current path pill
[Toolbar] — search input (col-4) | sort controls
[Table]   — Name | Size | Modified  (sortable headers)
            dirs listed first with folder icon
            files with download cursor
[Footer]  — entry count, total size
```

Table header sort toggle:
```html
<th @click="toggleSort('name')" class="clickable">
  Name <span :class="['sort-icon', sortKey==='name' && 'active']">
    {{ sortKey==='name' ? (sortDir==='asc' ? '▲' : '▼') : '⇅' }}
  </span>
</th>
```

---

## 10. Build & Run (WSL)

```bash
# Install Zig (if not present)
snap install zig --classic --edge
# or download tarball to ~/.local/zig

# Build
cd /project-root
zig build

# Run (serve current dir on :8080)
./zig-out/bin/dirindex --root /your/path --port 8080

# Quick test
curl http://localhost:8080/api/ls?path=/
```

**build.zig minimal:**
```zig
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "dirindex",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run");
    run_step.dependOn(&run.step);
}
```

---

## 11. Config via CLI Args

```zig
// parse std.process.argsAlloc
// --root <path>   default: cwd
// --port <num>    default: 8080
// --host <ip>     default: 0.0.0.0
```

---

## 12. Error Handling Conventions

- Return `404` JSON `{"error":"not found"}` for missing paths
- Return `403` JSON `{"error":"forbidden"}` for path traversal attempts
- Return `500` JSON `{"error":"internal"}` + log to stderr for unexpected errors
- Never crash the server on a bad request — recover per-connection
