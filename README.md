# dirz

A lightweight self-hosted directory browser. Single Zig binary, no Node/npm required.

## Features

- Browseable directory listing with sort by name, size, or modified date
- Live name filter
- File download
- Vue 3 frontend embedded in the binary — no separate static file serving needed
- Path traversal protection

## Requirements

- [Zig 0.15.2](https://ziglang.org/download/0.15.2/) (exactly — see note below)

> **Note:** Zig 0.16.0+ is not yet supported. The networking API (`std.net`) was overhauled in 0.16.0 and requires a significant rewrite. See [TODO](#todo).

## TODO

- [ ] Zig 0.16.0+ support — networking migrated to `std.Io` system

## Build

```bash
zig build
```

The binary is written to `./zig-out/bin/dirz`.

## Usage

```bash
./zig-out/bin/dirz [--root <path>] [--port <port>] [--host <host>]
```

| Flag | Default | Description |
|------|---------|-------------|
| `--root` | current directory | Directory to serve |
| `--port` | `8080` | Port to listen on |
| `--host` | `0.0.0.0` | Host/IP to bind |

Then open `http://localhost:8080` in a browser.

## API

| Endpoint | Description |
|----------|-------------|
| `GET /` | Web UI |
| `GET /api/ls?path=<path>` | JSON directory listing |
| `GET /files/<path>` | File download |

## License

MIT — see [LICENSE](LICENSE).
