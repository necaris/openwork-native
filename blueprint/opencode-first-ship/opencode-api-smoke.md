# OpenCode API Live Smoke — 2026-05-18

Smoke-tested against `opencode` v1.15.3 via `opencode serve --port 8765`.

## Verified routes

| Method | Path | Status | Notes |
| --- | --- | --- | --- |
| GET | `/global/health` | 200 | `{healthy: true, version}` |
| GET | `/session` | 200 | `[Session]` |
| POST | `/session` | 200 | body `{title}` → `Session` |
| GET | `/session/{id}/message` | 200 | `[{info, parts}]` |
| POST | `/session/{id}/prompt_async` | **204** | body `{parts: [{type: "text", text}]}` |
| POST | `/session/{id}/abort` | 200 | returns `true` |
| POST | `/session/{id}/permissions/{permID}` | 200 | body `{response: "once" \| "always" \| "reject"}` |
| GET | `/file/status` | 200 | `[File]` |
| GET | `/provider` | 200 | `{all, default, connected}` (all three keys required) |
| GET | `/event` | 200 | text/event-stream |

The `directory` query param is required for workspace-scoped endpoints. The client already passes it.

## Session payload

Confirmed live against `opencode` 1.15.10 on `localhost:4096`:

```json
{
  "id": "ses_...",
  "slug": "quiet-nebula",
  "projectID": "...",
  "directory": "/Users/rami/Projects/openwork-native",
  "path": "",
  "summary": { "additions": 0, "deletions": 0, "files": 0 },
  "cost": 0,
  "tokens": {
    "input": 0,
    "output": 0,
    "reasoning": 0,
    "cache": { "read": 0, "write": 0 }
  },
  "title": "smoke",
  "agent": "build",
  "model": { "id": "mercury-edit-2", "providerID": "inception", "variant": "default" },
  "version": "1.15.3",
  "time": { "created": 1779152995626, "updated": 1779152995736 }
}
```

`time.created` is milliseconds since epoch — the client divides by 1000 already.

## Message info payload

User and assistant `info` blocks have **different shapes**. The client
must handle both.

User-message `info` (sparse):

```json
{
  "id": "msg_...",
  "sessionID": "ses_...",
  "role": "user",
  "time": { "created": 1779152995671 },
  "summary": { "diffs": [] },
  "agent": "build",
  "model": { "providerID": "inception", "modelID": "mercury-edit-2" }
}
```

Assistant-message `info` (rich):

```json
{
  "id": "msg_...",
  "sessionID": "ses_...",
  "parentID": null,
  "role": "assistant",
  "time": { "created": ..., "completed": ... },
  "cost": 0,
  "tokens": {
    "input": 0,
    "output": 0,
    "reasoning": 0,
    "cache": { "read": 0, "write": 0 }
  },
  "modelID": "mercury-edit-2",
  "providerID": "inception",
  "mode": "...",
  "agent": "build",
  "path": { "cwd": "...", "root": "..." },
  "error": { "name": "APIError", "data": { "message": "...", "isRetryable": true, "responseBody": "...", "responseHeaders": {...}, "statusCode": 400, "metadata": {"url": "..."} } }
}
```

Notable inconsistencies:

- User info wraps model as `model: {providerID, modelID}`; assistant info
  exposes them flat as top-level `modelID` and `providerID`.
- `tokens`/`cost` exist on assistant info, not user info.
- `time.completed` is present only on assistant info.
- `error` appears only on a failed assistant turn (schema: name, data with
  HTTP statusCode, responseBody, isRetryable).

## Event types observed

`server.connected`, `session.created`, `session.updated`, `session.status`, `session.idle`,
`session.diff`, `session.error`, `session.next.agent.switched`, `session.next.model.switched`,
`message.updated`, `message.part.updated`.

The OpenAPI schema also defines `message.part.delta`, `permission.asked`, `permission.replied`,
`todo.updated`, and many `session.next.*` fine-grained streaming events.

## Mismatches found and fixed in this pass

1. **Permission event name and shape**. The client previously listened for
   `permission.updated` with fields `{title, pattern, metadata}`. The real event
   is `permission.asked` with `{permission, patterns[], metadata, always[]}`
   (schema `PermissionRequest`). Updated `OpenCodeEvent.permissionRequest`
   and `AppState.apply` accordingly.

2. **`permission.replied` event**. Now handled so that resolved permission
   requests are removed from the queue if the reply arrives via the event
   stream (e.g. resolved in another client).

3. **`message.part.delta` streaming**. The OpenAPI schema defines an
   incremental delta event with `{sessionID, messageID, partID, field, delta}`.
   The previous code only handled snapshot `message.part.updated` events.
   `AppState.applyMessagePartDelta` now appends deltas keyed by `partID`.

## Status visibility verification (2026-05-27, `#638518c`)

Re-verified against `opencode` 1.15.10 on `localhost:4096`. The data
needed for model/tokens/cost visibility is present on the wire today;
the client just discards it. Findings used to scope `#5b3c0fc`:

- Session-level `cost` (number, USD) and `tokens.{input,output,reasoning,cache.{read,write}}` are populated by the server and are intended as running totals.
- Assistant message info carries its own `cost` and `tokens` (same shape), so per-turn breakdowns are possible without further requests.
- Model identity is on both surfaces but in two formats: session `model: {id, providerID, variant}` vs. assistant info flat `modelID` + `providerID`. The client needs to normalise both.
- `summary` blocks: session-level has `{additions, deletions, files}` (useful for the "files changed by session" requirement in spec §7); message-level has `{diffs}` for per-turn diffs.
- Assistant info exposes `mode`, `agent`, and `path: {cwd, root}` — surfaceable in tooltips but not on the critical path for `#5b3c0fc`.
- Failed turns include a structured `error: {name, data: {message, isRetryable, statusCode, responseBody, responseHeaders, metadata}}` block. The Activity/banner currently shows none of this; worth wiring into the failure-handling path.
- `/event` stream begins with `server.connected` (no `properties`); other events were not captured live during this snapshot because no session was actively prompted. `session.updated`, `session.next.model.switched`, and `session.next.agent.switched` are still to be observed under load — punt to `#5b3c0fc` implementation when a real prompt is in flight.

## Still to validate (outside this issue)

- `session.next.*` fine-grained events for the Activity panel — `#20d3fd5`.
- `provider.auth` / `auth/{providerID}` write path for in-app config — `#e4811fd`.
- The OpenAPI also exposes `/api/session*` variants alongside `/session*`; the
  client uses the unprefixed routes which work today, but the `/api/*` form
  may be the long-term path. Re-verify if upstream deprecates `/session`.
