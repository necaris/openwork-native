# OpenWork Native

A native macOS desktop client for [OpenCode](https://opencode.ai), inspired by
[OpenWork](https://different.ai) from Different.AI. Local-first: the app talks
directly to a locally-supervised OpenCode server against a folder you choose —
no cloud control plane, no hosted workers.

> **Status:** MVP / pre-alpha. See [SPEC.md](SPEC.md) for scope and
> non-goals. Expect breakage.

## What it does

- Pick a local project folder and remember recent workspaces.
- Start, supervise, and stop a local OpenCode server bound to that workspace.
- Create, list, and open OpenCode sessions; send prompts and stream responses.
- Render markdown transcripts with copy / retry.
- Surface plan steps, tool calls, and file-change activity as the agent works.
- Prompt for permission when OpenCode requests a tool/path (allow once, deny,
  always allow).
- Configure the default model/provider and surface OpenCode auth errors.
- Reveal changed files in Finder or open them in your editor.

## Explicitly out of scope (MVP)

Cloud control plane, hosted workers, org/team provisioning, billing, remote
worker connection, UI-control MCP bridge, Slack/Telegram connectors, hosted
skill hubs, browser/mobile parity, multi-user workflow distribution. See
[SPEC.md](SPEC.md) for the full list.

## Requirements

- macOS 13 (Ventura) or later
- Swift 6.0 / Xcode 16+
- An [OpenCode](https://opencode.ai) binary on `PATH` (the app shells out to it
  for the local server)
- A configured model provider (API key) for OpenCode

## Build & run

```sh
mask build
swift run OpenWorkNative
```

Run lint and tests:

```sh
mask lint
mask test
```

Build a local unsigned `.app` bundle:

```sh
mask app
```

Open in Xcode:

```sh
open Package.swift
```

## Layout

```
Sources/OpenWorkNative/
├── OpenWorkNativeApp.swift     # SwiftUI app entry point
├── AppState.swift              # Top-level observable state
├── Models.swift                # Session, message, permission types
├── Services/
│   ├── OpenCodeProcessManager  # Spawns / supervises the local OpenCode server
│   ├── OpenCodeClient          # HTTP + SSE client against the server
│   └── WorkspaceStore          # Recent-workspace persistence
└── Views/
    ├── ContentView             # Root layout
    ├── SidebarView             # Workspace + session list
    ├── TranscriptView          # Composer + streamed messages
    ├── ActivityView            # Plan / tool-call timeline
    └── SettingsView            # Model, provider, permissions
```

## Architecture

The native app is the only process boundary. It manages an OpenCode server as
a child process and talks to it directly over its local API:

```
Native app
  └─ UI, workspace picker, process manager, prefs, keychain
       │
       ▼
  local OpenCode server
       └─ sessions · SSE events · permissions · file/status · workspace files
```

An intermediate server may be introduced later if remote workers or stronger
abstraction become necessary; for the MVP it is deliberately absent.

## Credits

Inspired by [OpenWork](https://different.ai) (Different.AI). Built on top of
[OpenCode](https://opencode.ai).
