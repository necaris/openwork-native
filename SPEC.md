# OpenWork Native MVP Spec

## Scope

Build a *native macOS*, local-first OpenCode desktop app inspired by OpenWork.

Explicitly excluded from this MVP:

- cloud control plane
- hosted/cloud workers
- org/team provisioning
- billing/checkout
- remote worker connection
- UI-control MCP bridge
- Slack/Telegram connectors
- hosted skill hubs
- browser/mobile parity
- multi-user workflow distribution

## Product Core

The MVP is a local desktop client that lets a user pick a project folder, run OpenCode against it, send agent prompts, observe execution, respond to permission requests and work with output. 

## MVP Features

### 1. Local Workspace Management

- Pick/open a local project folder.
- Remember recent workspaces.
- Show current workspace path and runtime status.
- Start/stop a local OpenCode server for that workspace.

Native app responsibilities:

- folder picker
- app lifecycle
- process supervision
- storing workspace metadata/preferences
- OS keychain integration where needed

### 2. OpenCode Session UI

OpenCode sessions are the app's task/run primitive.

Required:

- create a new session/task
- list previous sessions
- open a session
- send a prompt
- stream assistant output live
- stop/abort a running session
- view message history

### 3. Composer + Transcript

Minimum UX:

- chat-style prompt box
- visible running state 
- streamed assistant response & thinking
- markdown rendering
- copy message
- retry or send follow-up
- scroll-to-bottom behavior

Avoid overbuilding initially. The core product is: send work to the agent and watch the result.

### 4. Execution Visibility

The app should make agent work auditable.

MVP should show:

- plan/todo list if available
- current running step
- completed/failed steps
- tool-call summaries
- file changes/status if available

Initial UI can be a simple timeline or expandable activity panel.

### 5. Permission Handling

Required for trustworthy local execution.

MVP:

- listen for OpenCode permission requests
- display clear permission prompts
- allow once
- deny
- always allow

Permission prompt should show:

- requested action/tool
- target path or command
- reason/context if available
- session requesting it

### 6. Model/Provider Settings

MVP:

- view configured providers/models
- select default model
- surface OpenCode auth/config errors clearly

A full provider marketplace is completely out of scope.

### 7. File/Status Awareness

Basic workspace insight:

- changed files
- file status
- files changed by current session where available
- open file in external editor
- copy path
- reveal in Finder

A full file browser is deferred.

### 8. Skills/Commands/Plugins Manager

MVP may detect and display existing:

- `.agents/skills`
- commands
- plugins
- MCP config

Post-MVP:

- import skill folder
- edit `opencode.json`
- install curated skills
- reload OpenCode after config changes

## Architecture

For the native-only MVP, call OpenCode APIs directly from the native app backend/process rather than adding an OpenWork-style intermediate server.

```text
Native app
  ├─ workspace picker
  ├─ OpenCode process manager
  ├─ local app database/preferences
  ├─ OS keychain
  └─ UI

Native app
  -> local OpenCode server
      -> sessions
      -> events/SSE
      -> permissions
      -> file/status APIs
      -> workspace files
```

An intermediate server can be introduced later if remote support or stronger abstraction becomes necessary.

## First Shippable Version

1. Open local folder.
2. Start/manage OpenCode.
3. Create/list/open sessions.
4. Send prompt and stream response.
5. Show activity/todos/tool progress.
6. Handle permission prompts.
7. Show changed files.
8. Configure model/API key enough to get running.

## Current Implementation Status (2026-05-14)

Implemented so far:

- Native SwiftUI shell for workspace, sessions, transcript, activity, settings and runtime controls.
- Recent workspace persistence.
- OpenCode process launch on an ephemeral localhost port with stdout/stderr capture and unexpected-exit reporting.
- Async OpenCode HTTP client for sessions, messages, prompt send, abort, permission replies, changed files, providers/models and event stream setup.
- SSE parsing and event handling for transcript deltas, reasoning/thinking parts, todos, tool calls, session status/errors, permissions and file-change refreshes.
- Markdown transcript rendering, message copy, changed-file actions and provider/auth error surfacing.
- Git-status fallback for changed files.
- Local unsigned `.app` packaging plus Swift tests for API/event parsing and git-status parsing.

Remaining before calling the MVP shippable:

- Validate the assumed OpenCode routes and event payloads against a live/current OpenCode install (`git issue #a62f634`).
- Add startup health polling, graceful app-quit shutdown and better runtime recovery (`#5a26fd5`).
- Finish model/provider settings write path or explicitly make first ship read-only with clear setup guidance (`#e4811fd`).
- Polish transcript/activity UX: code-block copy, retry/edit-resend, activity grouping/history caps and richer running-step transitions (`#20d3fd5`).
- Decide and implement any local persistent Always Allow permission policy (`#535e7d9`).
- Add read-only skills/commands/plugins/MCP inventory if time permits (`#fbd6b56`).
- Complete release hardening: lint availability, accessibility, dark-mode review and signing/notarization documentation (`#1898b86`). Raw Swift Testing discovery is confirmed with 7 passing tests.
