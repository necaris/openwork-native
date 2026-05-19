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

```
{id, slug, projectID, directory, path, cost, tokens, title, version, time: {created, updated}}
```

`time.created` is milliseconds since epoch — the client divides by 1000 already.

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

## Still to validate (outside this issue)

- `session.next.*` fine-grained events for the Activity panel — `#20d3fd5`.
- `provider.auth` / `auth/{providerID}` write path for in-app config — `#e4811fd`.
- Health polling after `opencode serve` launch — `#5a26fd5`.
- The OpenAPI also exposes `/api/session*` variants alongside `/session*`; the
  client uses the unprefixed routes which work today, but the `/api/*` form
  may be the long-term path. Re-verify if upstream deprecates `/session`.
