# plat-verify VS Code Extension

Architecture conformance verification for plat manifests.

## Prerequisites

- `plat-verify` binary in PATH (build with `cargo build -p plat-verify`)
- A `plat-verify.toml` config file in your workspace
- A manifest JSON file (auto-detected as `*.plat.json` or `manifest.json`)

## Setup

```bash
cd editors/vscode
npm install
npm run compile
```

To run in development mode, press F5 in VS Code with this folder open.

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `plat-verify.serverPath` | `plat-verify` | Path to the plat-verify binary |
| `plat-verify.manifestPath` | (auto-detect) | Path to the manifest JSON file |
| `plat-verify.configPath` | `plat-verify.toml` | Path to the config file |

## Features

- Real-time architecture conformance diagnostics on file save
- Supports Go, TypeScript, and Rust source files
- Status bar indicator for server state
- `plat-verify: Restart` command to restart the language server
