# CONTEXT.md — dirz Working Context

## Current State
- Implementation complete, build succeeds
- Published on GitHub: https://github.com/jgseong/dirz
- Binary: `./zig-out/bin/dirz`

## Directory Structure
```
dirz/
├── build.zig
├── src/
│   ├── main.zig       # HTTP server + API
│   └── index.html     # Vue 3 SPA (embedded in binary via @embedFile)
├── public/
│   └── index.html     # Development reference (same as src/index.html)
├── CLAUDE.md          # Claude Code guidance (build, architecture, API, conventions)
├── CONTEXT.md         # This file
├── SKILLS.md          # Implementation pattern reference
├── README.md
├── LICENSE
├── CHANGES
└── VERSION            # 0.1.0
```

## Zig API Compatibility Notes
| Old API | New API |
|---|---|
| `std.heap.GeneralPurposeAllocator` | `std.heap.DebugAllocator` (renamed in Zig 0.14.0) |
| `std.ArrayList(T).init(alloc)` | `std.array_list.Managed(T).init(alloc)` |
| `std.json.stringify(v, .{}, writer)` | `std.json.Stringify.valueAlloc(alloc, v, .{})` |
| `stream.writer()` | `stream.writeAll(buf)` directly |
| `build.zig` `.root_source_file = b.path(...)` | `.root_module = b.createModule(.{ .root_source_file = ... })` |
| `@embedFile("../public/...")` | Cannot reference outside package root → files must be inside `src/` |

## Known Issues / TODO
- [ ] `/api/ls` may be slow on directories with many files (no pagination)
- [ ] HTTPS not supported
- [ ] Windows/Mac path separator handling not implemented (Linux/WSL only)

## Change History
1. Initial implementation (Zig HTTP server, Vue 3 SPA)
2. Zig API compatibility fixes (ArrayList, json, stream, embedFile)
3. Memory leak fix: `config.root` allocated with `config_arena` instead of GPA
4. `--root` with invalid path: clear error message + `exit(1)` instead of crash
5. Renamed project `dirix` → `dirz`
6. Added README, LICENSE, CHANGES, VERSION, .gitignore
7. Added CLAUDE.md, CONTEXT.md, SKILLS.md; removed Claude.md
8. Fix: `DebugAllocator` replaces `GeneralPurposeAllocator` (Zig 0.14.0+)
