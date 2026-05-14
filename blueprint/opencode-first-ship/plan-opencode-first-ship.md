# OpenCode First-Shippable Integration Plan

## Overview

- Focus on the critical path from the current SwiftUI scaffold to a first shippable local `.app`.
- Build the native macOS, local-first OpenCode desktop app described in `SPEC.md`.
- Treat OpenCode as the source of truth for sessions, messages, permissions, config, file status, and agent events.
- Call the local OpenCode server directly from the native app; do not add an OpenWork-style intermediate server.
- Verify the current OpenCode API surface before locking endpoint names, payload shapes, and SSE event handling.
- Keep the MVP exclusions explicit: no cloud control plane, hosted workers, org provisioning, billing, remote workers, UI-control MCP bridge, Slack/Telegram connectors, hosted skill hubs, browser/mobile parity, or multi-user workflow distribution.
- Ship enough native packaging for a local unsigned `.app`, with entitlements and hardened-runtime decisions documented.

## Expected behavior

- A user can pick/open a local project folder.
- The app remembers recent workspaces.
- The sidebar shows the current workspace path and runtime status.
- A user can start and stop a supervised OpenCode server for the selected workspace.
- The app launches OpenCode on an available ephemeral localhost port each run and stores that base URL in app state.
- The runtime captures stdout/stderr and detects unexpected exits.
- If OpenCode is missing or cannot launch, the app shows a clear runtime error.
- If OpenCode exits unexpectedly, the app marks the runtime failed, stops running sessions locally, and shows captured error output.
- The session list is loaded from OpenCode, using OpenCode-owned session IDs rather than local UUID-only records.
- A user can create, list, open, and select sessions backed by OpenCode.
- Opening a session shows session metadata first, then lazy-loads messages with loading/error states.
- A user can send a prompt and see assistant output stream into the transcript live.
- A user can abort a running session and see local UI state settle correctly.
- The composer remains chat-style, supports follow-up prompts, shows visible running state, and keeps scroll-to-bottom behavior.
- Transcript messages render markdown, allow copying, and distinguish assistant output from thinking/reasoning when OpenCode exposes it.
- Retry remains in scope for the MVP transcript UX, but can follow the core send/stream/abort path if necessary.
- Permission requests from OpenCode appear in the existing Permissions section while the stream stays connected.
- Permission prompts show the requested action/tool, target path or command, reason/context when available, and requesting session.
- A user can allow once, deny, or choose always allow when supported by the verified OpenCode permission API.
- Persistent “always allow” rule storage is deferred unless OpenCode already provides the behavior directly.
- Todo/plan updates appear as `ActivityItem(kind: .todo)` rows in the existing Activity list.
- Activity also surfaces current running step, completed/failed steps, tool-call summaries, file changes/status, and errors when OpenCode events provide them.
- Changed files are loaded from OpenCode file/status APIs when available, with `git status` as a fallback.
- File actions continue to support open in external editor, copy path, and reveal in Finder.
- Model/provider settings read and display existing OpenCode configuration only; in-app config editing and API key entry are deferred for this first ship.
- Auth/config errors appear as a main-window banner plus details in Settings.
- The first ship does not need a full file browser, skill importer, plugin editor, provider marketplace, or curated skill installer.
- Existing skills, commands, plugins, and MCP config may be detected read-only if cheap, but they are not on the critical path.
- The app can be built as a local `.app` bundle, even if signing/notarization is deferred.

## Status snapshot (2026-05-14)

The first-shippable integration plan is implemented in the codebase at a
pre-alpha level: the app builds, has an async OpenCode HTTP client, launches a
local OpenCode process, parses SSE events, streams transcript updates, resolves
permissions, loads provider/status data, and has unit coverage for parsers and
DTO mapping.

The remaining work is tracked in `git issue` and summarized in `TODO.md`:

- `#a62f634` Verify OpenCode API contract and live smoke path.
- `#5a26fd5` Harden runtime and workspace lifecycle.
- `#e4811fd` Finish model/provider settings write path.
- `#20d3fd5` Polish transcript and activity UX.
- `#535e7d9` Persist and manage permission always-allow policy.
- `#fbd6b56` Add read-only skills commands plugins and MCP inventory.
- `#1898b86` Release hardening accessibility and packaging.

Verification note: raw `swift test --enable-swift-testing ...` passes 7 tests;
any earlier `0 passed` summary was harness aggregation noise rather than test
discovery failure.

## Changes

- [~] Verify OpenCode APIs and document the confirmed routes/events for sessions, messages, streaming, abort, permissions, config, models/providers, file status, and event/SSE activity. _Implemented against assumed/current routes; live validation remains in `#a62f634`._
- [x] Replace `OpenCodeClient` stubs with an async HTTP/SSE client backed by `URLSession`.
- [x] Add API DTOs and mapping code from OpenCode payloads into existing app models.
- [x] Change `OpenCodeSession.id` from local-only `UUID` semantics to OpenCode-owned session identifiers.
- [~] Add loading and error states for session list, selected-session history, transcript stream, settings, permissions, and changed files. _Error banner exists; richer per-list loading/error states remain in `#20d3fd5` / `#1898b86`._
- [x] Update `AppState.openWorkspace`, `createSession`, `sendPrompt`, and `stopSelectedSession` to call real async client methods.
- [~] Track per-session streaming tasks so abort and workspace/session switches cancel cleanly. _Global event and message tasks exist; live cancellation semantics still need smoke validation in `#a62f634`._
- [x] Add an SSE parser that can append assistant deltas, surface errors, separate thinking content when available, and translate todo events into activity rows.
- [x] Add message-history loading on session selection.
- [x] Add markdown rendering for transcript content with SwiftUI `AttributedString(markdown:)` fallback behavior.
- [x] Add permission event decoding and a response path for allow-once, deny, and API-supported always-allow decisions.
- [ ] Add local persistent always-allow rule management if OpenCode does not provide sufficient persistence (`#535e7d9`).
- [~] Extend `OpenCodeProcessManager` to choose an available ephemeral port, launch OpenCode with that port, capture stdout/stderr, and notify `AppState` on unexpected termination. _Startup health polling, graceful app-quit shutdown, and restart UX remain in `#5a26fd5`._
- [x] Add runtime error presentation for missing OpenCode, failed launches, unexpected exits, and captured stderr details.
- [x] Add a main-window banner/error surface for OpenCode auth/config failures, with read-only information in `SettingsView`.
- [x] Add a changed-file service that prefers OpenCode status data and falls back to parsing `git status --porcelain` in the workspace.
- [~] Add read-only provider/model config loading from OpenCode or its config source, without editing or keychain entry in this pass. _Write/persist behavior is `#e4811fd`._
- [x] Preserve and wire existing workspace behavior: folder picker, recent workspaces, current workspace path, and runtime controls.
- [x] Preserve and wire existing file actions: open externally, reveal in Finder, and copy path.
- [ ] Add read-only detection for `.agents/skills`, commands, plugins, and MCP config (`#fbd6b56`).
- [x] Add a test target in `Package.swift`.
- [x] Add unit tests for API decoding, SSE parsing, permission decoding, and git-status parsing.
- [~] Add service-level tests using mocked networking and process-running abstractions. _Mocked networking tests exist; process-running abstraction/tests remain release-hardening work._
- [x] Add minimal `.app` bundle support with Info.plist/app metadata.
- [ ] Document signing/notarization/hardened-runtime decisions beyond local unsigned builds (`#1898b86`).
- [x] Keep UI changes incremental by reusing `TranscriptView`, `ActivityView`, `SidebarView`, and `SettingsView` rather than redesigning the shell.
