# UI plan: session/message status visibility

Issue: `#eae0151`. Predecessor: `#638518c` (live verification, closed).
Successor: `#5b3c0fc` (implementation).

## Goal

Make the model in use, accumulated token counts, and running cost visible
in the OpenWork UI so a user running an OpenCode session can answer at a
glance: *what model is this, how much have I spent, how much have I used*.
The data exists on the wire today (see
[opencode-api-smoke.md](opencode-api-smoke.md)); we just need to surface it.

## Decisions

### 1. Per-session totals → transcript header

A single line above the transcript ScrollView, below the navigation title:

```
┌─ Transcript ──────────────────────────────────────────────────────┐
│ mercury-edit-2 · inception   12,438 tokens   $0.0431              │
├───────────────────────────────────────────────────────────────────┤
│ (message bubbles…)                                                │
```

- Left: model badge `<modelID> · <providerID>` (caption, secondary).
- Right: `{n} tokens` and `${cost}` (caption, monospaced digits).
- Updates from `session.updated` event payloads; reload via `loadSessions`
  on session-switch.
- Click/hover (tooltip) reveals cache breakdown: `input N · output N · reasoning N · cache read N / write N`.

**Why here, not the sidebar.** The sidebar Workspace card already carries
runtime status and the green dot; piling cost/model on top of it makes the
mental model fuzzy ("am I looking at the runtime or the session?"). The
transcript header is the same scope as the messages below it, and it stays
visible as the user scrolls input/output.

**Rejected alternatives.**
- Sidebar session row: too cramped; the row already has title + date and
  is rendered in a tight `List`. Long model IDs would truncate.
- Floating HUD: more chrome than the data warrants for an MVP.
- Below the composer: invisible while scrolling history.

### 2. Per-message status → footer on assistant bubbles only

In `MessageBubble` for `role == .assistant`, append a footer row under
the content:

```
┌─ assistant ─────────────────────────────── 📋 ─┐
│ Sure, here's how to do that...                 │
│ ```swift                                       │
│ let x = 42                                     │
│ ```                                            │
│ ── mercury-edit-2 · 1,204 in / 318 out · $0.0061 · 1.2s ──
└────────────────────────────────────────────────┘
```

- `caption2`, secondary colour; separated by an em dash run or a thin Divider.
- Fields, in order: model, `{in} in / {out} out`, cost, latency
  (`time.completed - time.created`).
- If the assistant turn has `info.error`, replace the footer with a red
  inline error chip showing `error.data.message` (truncated) and a
  disclosure for the full body. This is currently invisible — the failed
  smoke run we captured had `mercury-edit-2` rejected by the upstream API
  and the user has no way to see why.

User-message bubbles get no footer (no model/tokens/cost attached).

**Rejected alternatives.**
- Tooltip-only: hides cost/tokens from anyone who doesn't think to hover.
- Sidebar-only aggregation: hides which turn was expensive.

### 3. Mid-session model switches

`session.next.model.switched` events fire when the active model changes
mid-conversation (manual switch, auto fallback, etc.). Handling:

- Update the session's `currentModel` in memory so the transcript header
  re-renders.
- Emit an `ActivityItem(kind: .runtime, title: "Model switched", detail: "<old> → <new>", state: <new>)`.
- **No inline transcript divider.** Decision: keep the transcript clean.
  The header already updates, and the activity timeline is the right
  place for runtime-state events.

Same for `session.next.agent.switched` → `Activity` row with the agent
name; don't try to show agents in the header (model is enough chrome).

### 4. Number formatting

- **Tokens.** Locale-grouped integer via `Int.formatted(.number)`.
  Default locale rendering ("1,234,567"). Never abbreviate to "1.2K" —
  developers want the exact number.
- **Cost.** USD via `Double.formatted(.currency(code: "USD"))`. Override
  fraction digits: 2 normally, **4 when total < $0.01** so sub-cent runs
  still show non-zero ("$0.0034"), "—" when null/zero and the turn hasn't
  completed.
- **Latency.** Seconds with one decimal (`1.2s`), milliseconds when
  `< 0.1s` (`87ms`).
- **Cache tokens.** Hidden by default, surfaced in the header tooltip
  only. Not promoted to the bubble footer — too noisy.

### 5. Empty / streaming / unknown states

- On session select, before any data has loaded: header shows `— · —` with
  the configured-default model name greyed out. No flicker into placeholders.
- Per-message footer renders as soon as `time.created` exists on the
  assistant info; token/cost values show `—` until populated. The footer
  must not appear-then-disappear.
- If `cost == 0` and the turn is complete, render `$0.00` (not `—`) so
  the user knows it really was free.

## Out of scope for `#5b3c0fc`

- Provider-cost split (per-provider totals across sessions). Defer.
- Token-budget warnings or quotas. Defer.
- Session-level files/lines `summary` row in the header. Spec §7 covers
  changed-files separately; mixing them here muddies the scope. File a
  follow-up if we want it on the header.
- Persistent per-workspace cost log. Defer to post-MVP.

## Acceptance for the implement issue

Implementation (`#5b3c0fc`) is done when:

1. With a live `opencode serve` and a real prompt, the transcript header
   updates `tokens` and `cost` as messages stream.
2. Each assistant bubble shows its own model, tokens, cost, and latency.
3. Failed turns show the upstream API error inline on the bubble.
4. A `session.next.model.switched` event during the session updates the
   header model badge and inserts an Activity row.
5. New decoders cover the user-vs-assistant model-shape inconsistency
   captured in the smoke doc.
6. Unit tests pass for: decoding a full session payload with cost/tokens,
   decoding both user and assistant message-info shapes, decoding the
   failed-turn error block, and applying `session.updated` to in-memory
   state.

## Open questions to confirm during implementation

- Does `session.updated` carry the full Session payload, or only deltas?
  (Live capture under load needed; the smoke run only got
  `server.connected`.) Implementation should handle "full snapshot"
  defensively until confirmed.
- Is `info.error` ever populated on a *non-fatal* assistant turn (e.g.
  partial completion with a tool-call retry)? If so the bubble must not
  hide the content while showing the error chip.
