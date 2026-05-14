# OpenWork Native — TODO

Scoped to the MVP defined in [SPEC.md](SPEC.md). Items below are derived by
diffing the spec against what currently lives in `Sources/OpenWorkNative/`.

Legend: `[x]` shipped · `[~]` partial / stubbed · `[ ]` not started.

---

## 0. Project plumbing

- [x] SwiftPM package, macOS 13+, single executable target
- [x] SwiftUI app entry point + `NavigationSplitView` shell
- [x] `AppState` as top-level `ObservableObject`
- [x] `.gitignore`, `README.md`, `SPEC.md`
- [ ] App bundle target (Info.plist, entitlements, code signing) — current build is a SwiftPM CLI binary, not a `.app`
- [ ] Sandbox / hardened-runtime decision (entitlements for file access, network client, child processes)
- [ ] `swift test` target + first unit tests (none exist today)
- [ ] CI (build + test) on macOS runner
- [ ] Logging facility (`os.Logger`) — currently no logs anywhere
- [ ] Crash / error reporting strategy (even if just `os_log` + user-facing alert)

---

## 1. Local Workspace Management — spec §1

- [x] Folder picker via `NSOpenPanel` — `AppState.pickWorkspace()`
- [x] Recent-workspaces list, persisted via `UserDefaults` (`WorkspaceStore`)
- [x] Display current workspace path + runtime status in sidebar
- [x] Start/Stop OpenCode buttons in toolbar
- [~] Process supervision — `OpenCodeProcessManager` only `Process().run()` / `terminate()`. Missing:
  - [ ] Capture stdout/stderr (`Pipe`) and surface in activity log
  - [ ] Detect crash / unexpected exit (`terminationHandler`) and update `runtimeStatus`
  - [ ] Health check (poll the local server endpoint after start)
  - [ ] Configurable port / discover the server's bound port instead of assuming defaults
  - [ ] Pass workspace path explicitly (currently relies on `currentDirectoryURL`)
  - [ ] Graceful shutdown on app quit (`NSApplication.willTerminate`)
  - [ ] Restart-on-failure policy (or at minimum a "Restart" button)
- [ ] Security-scoped bookmarks so recent workspaces survive sandboxing / relaunch
- [ ] Keychain integration for any per-workspace secrets (spec calls this out; nothing is wired)
- [ ] Validate workspace path still exists when re-opening from "Recent"
- [ ] Per-workspace preferences store (currently global `UserDefaults` only)

---

## 2. OpenCode Session UI — spec §2

- [x] Sidebar lists sessions, supports selection
- [x] "New Session" button creates an in-memory session
- [x] Send / Stop buttons in composer
- [~] `OpenCodeClient` is a placeholder — returns one hardcoded session, no HTTP. Required:
  - [ ] Real HTTP client (`URLSession`) targeting the local OpenCode server's base URL
  - [ ] `GET /session` (or equivalent) to list sessions on workspace open
  - [ ] `POST /session` to create
  - [ ] `GET /session/{id}/messages` to load history when opening an existing session
  - [ ] `POST /session/{id}/message` to send prompts
  - [ ] `POST /session/{id}/abort` (or equivalent) to stop a running session
  - [ ] `DELETE /session/{id}` if we want delete (post-MVP-ish, but cheap)
  - [ ] Error model + surfacing (network down, server not running, 4xx/5xx)
- [ ] Replace placeholder messages in `AppState.createSession` / `sendPrompt` with real responses
- [ ] Persist last-selected session per workspace
- [ ] Resolve and verify the actual OpenCode HTTP API surface against current OpenCode docs before locking endpoint shape

---

## 3. Composer + Transcript — spec §3

- [x] Chat-style prompt box (`TextField` axis: vertical, 2–6 lines)
- [x] Cmd+Return shortcut to send
- [x] Streaming indicator (`ProgressView` next to role)
- [x] Copy-message button per bubble
- [x] Auto-scroll to latest on message append
- [x] Empty-state view
- [ ] **Real SSE stream** from OpenCode → progressively append to the assistant message (today `sendPrompt` just inserts a static placeholder string)
  - [ ] SSE parser (`URLSession` data task with line-delimited parsing, or `URLSession` async bytes)
  - [ ] Reconnect / cancellation semantics tied to the session lifecycle
- [ ] **Markdown rendering** — current `Text(message.content)` renders raw text. Use SwiftUI `Text(AttributedString(markdown:))` at minimum, ideally a richer renderer for code blocks + syntax highlighting
- [ ] Code-block rendering with copy button
- [ ] "Retry" action on the last assistant turn
- [ ] "Edit & resend" on a user message (spec implies follow-up; nice to have)
- [ ] Distinguish "thinking" / reasoning content from final assistant text if OpenCode emits it separately
- [ ] Streaming cancellation actually cancels the upstream request (today `stopSelectedSession` only flips a local bool)
- [ ] Token / cost / model-name metadata on each turn (if surfaced by OpenCode)

---

## 4. Execution Visibility — spec §4

- [~] `ActivityView` exists with sections for Permissions, Activity, Changed Files
- [~] `ActivityItem` model has `step | tool | todo | file | runtime` kinds, but only `runtime` and `step` are ever produced (from local UI events)
- [ ] Subscribe to OpenCode's event/SSE stream and translate events into `ActivityItem`s:
  - [ ] Plan / todo list (kind: `.todo`) with checked / unchecked / failed states
  - [ ] Current running step (kind: `.step`) with start/stop transitions, not just append-only log
  - [ ] Tool-call summaries (kind: `.tool`) — name, inputs (truncated), result/exit
  - [ ] File-change events (kind: `.file`) — path, add/modify/delete
- [ ] Group activity by session (today it's a single global list)
- [ ] Collapse/expand for verbose tool calls
- [ ] Persist or at least cap activity history (currently unbounded in-memory)
- [ ] Clear activity when switching sessions / workspaces

---

## 5. Permission Handling — spec §5

- [~] UI rendering of pending requests with Allow Once / Deny / Always Allow — `ActivityView`
- [~] `resolvePermission(_:decision:)` removes the request locally and logs activity
- [ ] **Listen for real permission requests** from OpenCode — `permissionRequests` is never populated today
  - [ ] Identify the OpenCode permission event/endpoint (SSE event vs. polling vs. dedicated WS)
  - [ ] Decode payload into `PermissionRequest` (action, target path/command, reason, sessionId)
- [ ] **Send the decision back** to OpenCode — current resolver only updates local UI
- [ ] Persist "Always Allow" rules (per workspace, per tool, per path scope)
  - [ ] Storage layer for rules
  - [ ] Auto-resolve incoming requests that match a stored "always allow"
  - [ ] Settings UI to view / revoke stored rules
- [ ] Block the requesting session UI while a permission is pending (or at least surface it prominently)
- [ ] Map `sessionTitle` correctly — current model stores a title, but real requests will arrive with a session id
- [ ] Timeout / auto-deny behavior if app is backgrounded (decide policy)

---

## 6. Model / Provider Settings — spec §6

- [~] `SettingsView` renders providers, but `appState.providers` is a single hardcoded placeholder and the picker uses `.constant(...)` — selection does nothing
- [ ] Read configured providers/models from OpenCode (config endpoint or `opencode.json`)
- [ ] Make the model picker actually mutate state and persist
- [ ] Surface OpenCode auth errors (missing API key, expired token) inline in Settings *and* via a banner in the main window
- [ ] "Open opencode.json" / "Reveal config in Finder" affordance
- [ ] Keychain storage for API keys if the user enters one in-app (spec mentions keychain integration)
- [ ] Default-model selection persisted per workspace (or global, decide)

---

## 7. File / Status Awareness — spec §7

- [x] `ChangedFile` model + list section in `ActivityView`
- [x] Per-file actions: Open in external editor, Reveal in Finder, Copy Path
- [~] `OpenCodeClient.loadChangedFiles` always returns `[]`
- [ ] Wire to OpenCode's file-status / git-status endpoint (or shell out to `git status` against the workspace as a fallback)
- [ ] Subscribe to file-change events from the active session (spec: "files changed by current session where available")
- [ ] Status badges (added / modified / deleted / renamed) instead of free-text `status` string
- [ ] Refresh-on-focus or push-driven updates
- [ ] Filter to "files changed by this session" vs. "all dirty files in workspace"

---

## 8. Skills / Commands / Plugins Manager — spec §8

- [ ] Detect `.agents/skills/` in the workspace and list entries
- [ ] Detect commands directory and list
- [ ] Detect plugins directory and list
- [ ] Parse and display MCP config from `opencode.json`
- [ ] Read-only browser UI section (sidebar tab or settings pane — not yet decided)

Spec marks edit / import / install / hot-reload as **post-MVP** — leave out.

---

## Cross-cutting / quality

- [ ] Concurrency review — `AppState` is `@MainActor`, but services (`OpenCodeClient`, `OpenCodeProcessManager`) will need actor isolation once they do real I/O
- [ ] Replace synchronous stub APIs with `async`/`await` end-to-end
- [ ] Cancellation-correctness: every long-running stream should be `Task`-scoped to the session
- [ ] Error-presentation pattern (single `AlertCenter` or per-section banners) — currently errors only land in `runtimeDetail`
- [ ] Accessibility pass (VoiceOver labels on icon-only buttons, sufficient contrast)
- [ ] Dark-mode visual review
- [ ] Keyboard shortcuts beyond Cmd+Return (new session, switch session, focus composer, stop)
- [ ] Empty / loading / error states for every list (`sessions`, `activity`, `changedFiles`, `providers`)

---

## "First Shippable Version" checklist — spec §First Shippable Version

Direct mapping for release-readiness:

1. [x] Open local folder
2. [~] Start/manage OpenCode — starts a process; no health check, no log capture, no crash handling
3. [~] Create / list / open sessions — UI exists; backend returns stubs
4. [ ] Send prompt and stream response — **not wired** (placeholder string only)
5. [~] Show activity / todos / tool progress — UI exists; only local runtime events flow through it
6. [~] Handle permission prompts — UI exists; no listener, no responder
7. [~] Show changed files — UI exists; data source returns `[]`
8. [~] Configure model / API key enough to get running — read-only placeholder; picker is non-functional

**Critical path to shippable:** items 4, 5, 6, 7, 8 above — i.e. replace
`OpenCodeClient` and the permission/event plumbing with real OpenCode API
calls, plus make the Settings model picker actually persist a selection.
