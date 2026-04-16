# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
zig build
./zig-out/bin/dirz --root /path/to/serve --port 8080
# or
zig build run -- --root /path/to/serve --port 8080
```

Flags: `--root` (default: cwd), `--port` (default: 8080), `--host` (default: 0.0.0.0)

Test:
```bash
curl "http://localhost:8080/api/ls?path=/"
```

## Architecture

Single Zig binary, no Node/npm/reverse proxy.

```
[Browser]
   │  Vue 3 SPA (CDN deps, no build step)
   ▼
[Zig HTTP server]  :8080
   ├── GET /               → embedded src/index.html (@embedFile)
   ├── GET /api/ls?path=   → JSON directory listing
   └── GET /files/<path>   → streamed file download
   ▼
[Filesystem]  (configured root, path-traversal protected)
```

- `src/main.zig` — entire backend: HTTP parsing, routing, fs, file serving
- `src/index.html` — entire frontend, embedded into binary at compile time; changes require rebuild
- `public/index.html` — dev reference copy, not served by the binary

## API

`GET /api/ls?path=<url-encoded-path>`
```json
{
  "path": "/docs",
  "entries": [
    { "name": "readme.txt", "type": "file", "size": 2048, "modified": 1713200000 },
    { "name": "images",     "type": "dir",  "size": 0,    "modified": 1713100000 }
  ]
}
```

Errors return `{"error":"<message>"}` with appropriate HTTP status (403 forbidden, 404 not found, 500 internal).

## Key Implementation Details

**Memory:** GPA for server lifetime; per-request `ArenaAllocator` freed at connection end; config strings in a separate `config_arena`.

**Path traversal protection:** `std.fs.realpathAlloc` + `std.mem.startsWith(resolved, config.root)` on every request before any fs access.

**Concurrency:** one detached `std.Thread` per connection, no pool.

**Zig 0.15.2 API:**
- `std.heap.DebugAllocator(.{})` — renamed from `GeneralPurposeAllocator` in Zig 0.14.0
- `std.array_list.Managed(T).init(allocator)` — not `std.ArrayList(T).init`
- `std.json.Stringify.valueAlloc(allocator, value, .{})` — not `std.json.stringify`
- `stream.writeAll(buf)` — `stream.writer()` unavailable
- `build.zig` requires `.root_module = b.createModule(.{ .root_source_file = ... })`
- `@embedFile` cannot reference paths outside package root — frontend must stay in `src/`

## UI Conventions

Bootstrap 5 via CDN only; overrides in inline `<style>` block.
- `border-radius: 0` everywhere, dense padding (`0.2rem 0.5rem` on table cells)
- Dark navbar (`#1a1a2e`), white content area, monospace fonts throughout
- Dirs listed before files; sortable columns with `▲ ▼ ⇅` indicators
