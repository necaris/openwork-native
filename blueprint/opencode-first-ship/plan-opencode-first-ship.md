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

## Changes

- Verify OpenCode APIs and document the confirmed routes/events for sessions, messages, streaming, abort, permissions, config, models/providers, file status, and event/SSE activity.
- Replace `OpenCodeClient` stubs with an async HTTP/SSE client backed by `URLSession`.
- Add API DTOs and mapping code from OpenCode payloads into existing app models.
- Change `OpenCodeSession.id` from local-only `UUID` semantics to OpenCode-owned session identifiers.
- Add loading and error states for session list, selected-session history, transcript stream, settings, permissions, and changed files.
- Update `AppState.openWorkspace`, `createSession`, `sendPrompt`, and `stopSelectedSession` to call real async client methods.
- Track per-session streaming tasks so abort and workspace/session switches cancel cleanly.
- Add an SSE parser that can append assistant deltas, finish streamed messages, surface errors, separate thinking content when available, and translate todo events into activity rows.
- Add message-history loading on session selection after initial metadata display.
- Add markdown rendering for transcript content, at minimum with SwiftUI `AttributedString(markdown:)` or an equivalent lightweight renderer.
- Add permission event decoding and a response path for allow-once, deny, and API-supported always-allow decisions.
- Keep local persistent always-allow rule management out of the first ship unless the verified OpenCode API makes it trivial.
- Extend `OpenCodeProcessManager` to choose an available ephemeral port, launch OpenCode with that port, capture stdout/stderr, and notify `AppState` on unexpected termination.
- Add runtime error presentation for missing OpenCode, failed launches, unexpected exits, and captured stderr details.
- Add a main-window banner/error surface for OpenCode auth/config failures, with detailed read-only information in `SettingsView`.
- Add a changed-file service that prefers OpenCode status data and falls back to parsing `git status --porcelain` in the workspace.
- Add read-only provider/model config loading from OpenCode or its config source, without editing or keychain entry in this pass.
- Preserve and wire existing workspace behavior: folder picker, recent workspaces, current workspace path, and runtime controls.
- Preserve and wire existing file actions: open externally, reveal in Finder, and copy path.
- Optionally add read-only detection for `.agents/skills`, commands, plugins, and MCP config only after the first-ship path is stable.
- Add a test target in `Package.swift`.
- Add unit tests for API decoding, SSE parsing, permission decoding, and git-status parsing.
- Add service-level tests using mocked networking and process-running abstractions.
- Add minimal `.app` bundle support with Info.plist/app metadata and a documented entitlements/hardened-runtime decision.
- Keep UI changes incremental by reusing `TranscriptView`, `ActivityView`, `SidebarView`, and `SettingsView` rather than redesigning the shell.
