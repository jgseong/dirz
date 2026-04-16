# Context.md — dirz Working Context

## Current State
- Implementation complete, build succeeds, basic tests pass
- Binary: `./zig-out/bin/dirz`

## Running
```bash
zig build
./zig-out/bin/dirz --root /your/path --port 8080
```

## Directory Structure
```
dirz/
├── build.zig
├── src/
│   ├── main.zig       # HTTP server + API
│   └── index.html     # Vue 3 SPA (embedded in binary via @embedFile)
├── public/
│   └── index.html     # Development reference (same as src/index.html)
├── Claude.md          # Project requirements
├── Skills.md          # Implementation pattern reference
└── Context.md         # This file
```

## API
- `GET /` → Vue 3 SPA
- `GET /api/ls?path=<url-encoded-path>` → JSON directory listing
- `GET /files/<path>` → File download

## Zig 0.15.2 Key API Changes (already applied)
| Old API | New API |
|---|---|
| `std.ArrayList(T).init(alloc)` | `std.array_list.Managed(T).init(alloc)` |
| `std.json.stringify(v, .{}, writer)` | `std.json.Stringify.valueAlloc(alloc, v, .{})` |
| `stream.writer()` | Use `stream.writeAll(buf)` directly |
| `build.zig` `.root_source_file = b.path(...)` | `.root_module = b.createModule(.{ .root_source_file = ... })` |
| `@embedFile("../public/...")` | Cannot reference outside package path → place files inside `src/` |

## Known Issues / TODO
- [ ] `/api/ls` response may be slow on directories with many files (no pagination)
- [ ] HTTPS not supported
- [ ] Changes to `index.html` while binary is running are not reflected (embedded at build time, requires rebuild)
- [ ] Windows/Mac path separator handling not implemented (WSL only)

## Recent Change History
1. Initial implementation (Zig HTTP server, Vue 3 SPA)
2. Zig 0.15.2 API compatibility fixes (ArrayList, json, stream, embedFile)
3. Memory leak fix: allocate `config.root` with `config_arena` instead of GPA
4. `--root` with invalid path caused FileNotFound crash → clear error message + `exit(1)`
