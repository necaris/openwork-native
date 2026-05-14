# OpenWork Native — TODO

Scoped to the MVP in [SPEC.md](SPEC.md). This file is the human-readable
checklist; open work is mirrored in `git issue`.

Task tracking status: `.ba/` is not initialized in this repo, so the active
tracker is `git issue` plus this `TODO.md` summary.

Legend: `[x]` shipped · `[~]` partial / needs validation · `[ ]` remaining.

---

## Progress so far

- [x] SwiftUI macOS shell with workspace picker, sidebar, transcript, activity,
      settings, and toolbar runtime controls.
- [x] Recent workspaces persisted with `UserDefaults` via `WorkspaceStore`.
- [x] OpenCode process launch on an ephemeral localhost port.
- [x] OpenCode stdout/stderr capture with unexpected-exit reporting.
- [x] Async `OpenCodeClient` for sessions, messages, prompts, abort,
      permissions, changed files, provider/model data, and `/event` stream
      request construction.
- [x] OpenCode-owned session identifiers flow through app models.
- [x] Session list/create/open and lazy message-history loading.
- [x] Prompt send path using OpenCode `prompt_async`.
- [x] SSE parser plus event handling for message updates, message-part deltas,
      reasoning/thinking parts, session status/errors, permissions, todos, tool
      calls, and file-change refresh triggers.
- [x] Markdown transcript rendering with selectable/copyable message text.
- [x] Permission UI with Allow Once / Deny / Always Allow buttons wired to the
      OpenCode permission reply endpoint.
- [x] Changed-files UI and file actions: open, reveal in Finder, copy path.
- [x] Changed-file loading from OpenCode status with `git status --porcelain`
      fallback.
- [x] Read-only model/provider loading and auth/config error banner path.
- [x] Debug build, local unsigned `.app` bundle task, lint/test mask tasks.
- [x] Swift test target with coverage for API decoding, SSE parsing, permission
      decoding, and git-status parsing.

Verification evidence:

- `mask build` passes locally.
- Raw `swift test --enable-swift-testing ...` passes 7 tests locally.
- `mask test` exits successfully; any earlier `0 passed` summary was the harness
  output aggregator, not Swift test discovery.

---

## Git issue tracker

Tracked issues:

- [ ] `#a62f634` Verify OpenCode API contract and live smoke path — **high**, open/unblocked.
- [ ] `#5a26fd5` Harden runtime and workspace lifecycle — **high**, open/unblocked.
- [ ] `#e4811fd` Finish model/provider settings write path — **high**, blocked by `#a62f634`.
- [ ] `#20d3fd5` Polish transcript and activity UX — medium, blocked by `#a62f634`.
- [ ] `#535e7d9` Persist and manage permission always-allow policy — medium, open/unblocked.
- [ ] `#1898b86` Release hardening accessibility and packaging — medium, blocked by `#a62f634` and `#5a26fd5`.
- [ ] `#fbd6b56` Add read-only skills commands plugins and MCP inventory — low, open/unblocked.

Use:

```sh
git issue ready
git issue show <id>
git issue start <id>
git issue close <id>
```

---

## Remaining tasks by spec area

### 1. Local Workspace Management — spec §1

- [x] Folder picker via `NSOpenPanel`.
- [x] Recent-workspaces list persisted with `UserDefaults`.
- [x] Current workspace path and runtime status in sidebar.
- [x] Start/stop local OpenCode runtime controls.
- [~] Process supervision: stdout/stderr capture and unexpected-exit handling
      exist; remaining work is tracked in `#5a26fd5`.
  - [ ] Poll health after startup before declaring runtime fully ready.
  - [ ] Graceful shutdown on app quit.
  - [ ] Restart/recovery UX after unexpected exit.
  - [ ] Validate recent workspace path still exists before reopening.
  - [ ] Security-scoped bookmarks for sandboxed builds.
  - [ ] Decide per-workspace preferences shape.

### 2. OpenCode Session UI — spec §2

- [x] Sidebar lists OpenCode-backed sessions and supports selection.
- [x] Create a new OpenCode session.
- [x] Load message history for the selected session.
- [x] Send prompt and stop/abort selected session through the client.
- [~] Endpoint/event contract needs live OpenCode validation: `#a62f634`.
- [ ] Persist last-selected session per workspace.
- [ ] Add clearer per-list loading and error states.

### 3. Composer + Transcript — spec §3

- [x] Chat-style composer with Cmd+Return send.
- [x] Visible streaming/running state.
- [x] Live streamed assistant text/reasoning via SSE events.
- [x] Markdown rendering with selectable text.
- [x] Copy-message button per bubble.
- [x] Auto-scroll to latest message.
- [ ] Code-block rendering with per-block copy button: `#20d3fd5`.
- [ ] Retry last assistant turn: `#20d3fd5`.
- [ ] Edit/resend user message: `#20d3fd5`.
- [ ] Ensure upstream cancellation semantics are correct for every stream:
      `#a62f634` / `#20d3fd5`.

### 4. Execution Visibility — spec §4

- [x] Activity panel exists with Permissions, Activity, and Changed Files.
- [x] Todo, tool, runtime, step, error, and file-refresh events are mapped from
      OpenCode events where available.
- [ ] Validate actual OpenCode event shapes and fill any mapping gaps:
      `#a62f634`.
- [ ] Track current running step with updates instead of append-only rows:
      `#20d3fd5`.
- [ ] Group activity by session and cap/persist activity history: `#20d3fd5`.
- [ ] Collapse/expand verbose tool calls: `#20d3fd5`.

### 5. Permission Handling — spec §5

- [x] Permission requests can be decoded from OpenCode events.
- [x] Pending requests render with action, target, reason, session, and decisions.
- [x] Decisions are sent back to OpenCode.
- [~] Always Allow is sent to OpenCode; local persistent rule management remains
      open in `#535e7d9`.
- [ ] Auto-resolve stored always-allow rules if local policy is required.
- [ ] Settings UI to view/revoke stored rules if local policy is required.
- [ ] Define timeout/background behavior.

### 6. Model / Provider Settings — spec §6

- [x] Load providers/models from OpenCode read-only.
- [x] Show provider auth/connectivity status and main-window error banner.
- [~] Settings picker is currently read-only (`.constant(...)`); write/persist
      behavior is tracked in `#e4811fd`.
- [ ] Decide whether first ship edits OpenCode config or only links to external
      OpenCode setup.
- [ ] If in-app API key entry is added, store secrets in Keychain.
- [ ] Add “Open opencode.json” / “Reveal config in Finder” affordances.

### 7. File / Status Awareness — spec §7

- [x] Changed-file model/list section.
- [x] Open/reveal/copy file actions.
- [x] OpenCode status loading with git-status fallback.
- [~] File-change events currently trigger a refresh; validate exact event
      payloads in `#a62f634`.
- [ ] Filter “files changed by current session” vs all dirty workspace files.
- [ ] Add stronger status badges for add/modify/delete/rename.
- [ ] Refresh-on-focus policy if events are missed.

### 8. Skills / Commands / Plugins Manager — spec §8

- [ ] Detect `.agents/skills/` and list entries: `#fbd6b56`.
- [ ] Detect commands/plugins directories read-only: `#fbd6b56`.
- [ ] Parse and display MCP config from `opencode.json`: `#fbd6b56`.
- [ ] Keep import/edit/install/reload out of MVP unless scope changes.

---

## Cross-cutting / release hardening

- [ ] Live smoke test against an installed OpenCode server: `#a62f634`.
- [x] Confirm Swift Testing discovery: raw run passes 7 tests.
- [ ] Run lint when `swiftformat` and `swiftlint` are installed: `#1898b86`.
- [ ] Accessibility pass for icon-only controls and VoiceOver labels:
      `#1898b86`.
- [ ] Dark-mode visual review: `#1898b86`.
- [ ] Keyboard shortcuts for new session, switch session, focus composer, stop:
      `#20d3fd5`.
- [ ] Document signing/notarization/hardened-runtime posture beyond the local
      unsigned `.app`: `#1898b86`.
