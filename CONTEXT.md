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

## Zig Version

**Requires Zig 0.15.2.** Zig 0.16.0+ breaks the build — networking (`std.net`) was replaced by `std.Io` system.

## Zig 0.15.2 API Notes
| Old (pre-0.15) | Current (0.15.2) |
|---|---|
| `std.ArrayList(T).init(alloc)` | `std.array_list.Managed(T).init(alloc)` |
| `std.json.stringify(v, .{}, writer)` | `std.json.Stringify.valueAlloc(alloc, v, .{})` |
| `stream.writer()` | `stream.writeAll(buf)` directly |
| `build.zig` `.root_source_file = b.path(...)` | `.root_module = b.createModule(.{ .root_source_file = ... })` |
| `@embedFile("../public/...")` | Cannot reference outside package root → files must be inside `src/` |

## Known Issues / TODO
- [ ] Zig 0.16.0+ support — `std.net` replaced by `std.Io` networking system
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
8. Reverted Zig 0.14.x compatibility patches — targeting Zig 0.15.2 only
9. Added TODO for Zig 0.16.0+ migration (`std.Io` networking)
10. Browser back/forward navigation via `history.pushState` + `popstate`
11. File/dir names as `<a href>` — right-click copy link supported natively
12. Text file inline viewer modal (30+ extensions: txt, md, json, py, zig, ...)
