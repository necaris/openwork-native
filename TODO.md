# OpenWork Native — TODO

Brief synthesis of next steps for the MVP.

**Sources**

- Scope and MVP feature list: [SPEC.md](SPEC.md)
- User-facing status and build/run: [README.md](README.md)
- Implementation plan and per-task status: [blueprint/opencode-first-ship/plan-opencode-first-ship.md](blueprint/opencode-first-ship/plan-opencode-first-ship.md)
- Live API smoke results: [blueprint/opencode-first-ship/opencode-api-smoke.md](blueprint/opencode-first-ship/opencode-api-smoke.md)
- Active issue tracker: `git issue list` (`.ba/` is not initialized)

Legend: `[x]` shipped · `[~]` partial · `[ ]` remaining.

---

## Where we are

The first-shippable plan is implemented end-to-end at pre-alpha quality
(SwiftUI shell, async OpenCode HTTP/SSE client, supervised local process,
streaming transcript, permissions, activity, changed-files). `mask build`
and `mask test` pass (8 tests). API contract is live-validated against
opencode 1.15.3 (`#a62f634` closed).

Recently landed beyond the plan:

- `AppLog` (`os.Logger`) wired through state/client/process so the running
  `.app` is debuggable from Console.app.
- `OpenCodeProcessManager.locateOpenCode()` resolves the binary via the
  user's login-shell `PATH` (Homebrew/asdf-friendly) and surfaces a clear
  "OpenCode not found" banner at startup.

---

## Next steps, by priority

### P0 — finish runtime hardening (`#5a26fd5`, spec §1)

Required for a trustworthy first ship.

- [x] Resolve `opencode` via user shell `PATH` instead of launchd env.
- [x] Surface "OpenCode not found" at startup, not only on Start.
- [x] Poll `/health` after spawn before declaring runtime ready
      (landed in 7e6a9f9).
- [x] Graceful shutdown of the OpenCode child process on app quit
      (`applicationWillTerminate`, terminate + wait, fall back to kill).
- [x] Restart/recovery UX after unexpected exit ("Retry OpenCode" toolbar
      button when runtimeStatus is `.failed`).
- [x] Validate the recent-workspace path still exists before reopening;
      missing entries are pruned and the list is rewritten on load.

### P0 — session/message status visibility (model, tokens, cost)

Audit (this session): the client decodes only `{id, title, time.created}`
from `/session` and `{id, role, time.created}` from `/session/{id}/message`,
dropping `cost`, `tokens`, model ID, provider ID. `session.updated` and
`session.next.model.switched` events are silently ignored. Sidebar shows
workspace + runtime status only; message bubbles show role + content only.
Result: cost, token usage, and live model are invisible in the UI.

Three issues filed, dependency-chained verify → plan → implement:

- [x] `#638518c` Verify OpenCode session/message status fields against
      a live `opencode serve` — see [opencode-api-smoke.md](blueprint/opencode-first-ship/opencode-api-smoke.md).
- [x] `#eae0151` Plan UI placement and formatting — see
      [status-visibility-ui-plan.md](blueprint/opencode-first-ship/status-visibility-ui-plan.md).
- [x] `#5b3c0fc` Implement end-to-end decoders → models → events → views.

### P0 — model/provider write path (`#e4811fd`, spec §6)

The Settings picker was replaced with explicit read-only configuration:

- [x] Explicit read-only mode with "Reveal opencode.json in Finder" and
      clear setup guidance in Settings + the auth-error banner.
- [x] In-app default-model persistence to `opencode.json` is deferred.

Keychain entry for API keys stays out of scope unless option 1 is chosen.

### P1 — transcript/activity polish (`#20d3fd5`, spec §3 + §4)

- [x] Enter sends the current chat message; Shift+Return inserts newline (`#57ad8b6`).
- [x] Render conversation blocks in Markdown via MarkdownUI (`#33ef4a3`).
- [ ] Per-block "copy code" on fenced code in markdown.
- [ ] Retry last assistant turn; edit-and-resend user message.
- [ ] Update the current running step in place instead of appending.
- [ ] Group activity by session; cap history length.
- [ ] Collapse/expand verbose tool calls.
- [ ] Keyboard shortcuts: new session, switch session, focus composer, stop.

### P1 — permission always-allow policy (`#535e7d9`, spec §5)

OpenCode accepts "always" but does not persist per-workspace rules itself.

- [ ] Decide: rely on OpenCode session-scoped behavior, or add local
      persistent rules keyed by `(workspace, tool, target)`.
- [ ] If local: settings UI to view/revoke rules; auto-resolve on prompt.

### P2 — release hardening (`#1898b86`)

- [ ] Get `swiftformat` + `swiftlint` available in CI and locally; the
      `mask lint` gate currently no-ops when missing.
- [ ] Accessibility pass: VoiceOver labels for icon-only controls.
- [ ] Dark-mode visual review.
- [ ] Document signing/notarization/hardened-runtime posture beyond the
      local unsigned `.app`.

### P3 — read-only inventory (`#fbd6b56`, spec §8)

- [ ] Detect `.agents/skills/`, commands, plugins.
- [ ] Parse and display MCP entries from `opencode.json`.
- [ ] No import/edit/install in MVP.

---

## Tracker quick reference

```sh
git issue ready          # unblocked queue
git issue list           # all issues
git issue show <id>      # detail
git issue start <id>     # mark in_progress
git issue close <id>     # mark done
```

Current state (from `git issue list`):

| ID | State | Title |
|---|---|---|
| `#a62f634` | closed | Verify OpenCode API contract and live smoke path |
| `#5a26fd5` | closed | Harden runtime and workspace lifecycle |
| `#e4811fd` | closed | Finish model/provider settings write path |
| `#20d3fd5` | open / medium | Polish transcript and activity UX |
| `#535e7d9` | open / medium | Persist and manage permission always-allow policy |
| `#1898b86` | open / medium | Release hardening, accessibility, packaging |
| `#fbd6b56` | open / low | Add read-only skills/commands/plugins/MCP inventory |
| `#57ad8b6` | closed | Enter sends current chat message by default |
| `#33ef4a3` | closed | Render conversation blocks in Markdown |
| `#638518c` | closed | Verify OpenCode session/message status fields |
| `#eae0151` | closed | Plan UI for session/message status |
| `#5b3c0fc` | closed | Implement session/message status visibility |

The "blocked" entries were blocked on `#a62f634`; they can now be unblocked
in the tracker.
