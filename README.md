# dirz

A lightweight self-hosted directory browser. Single Zig binary, no Node/npm required.

## Features

- Browseable directory listing with sort by name, size, or modified date
- Live name filter
- File download
- Vue 3 frontend embedded in the binary — no separate static file serving needed
- Path traversal protection

## Requirements

- [Zig 0.15.x](https://ziglang.org/download/)

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
