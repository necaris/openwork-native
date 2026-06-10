# OpenWork Native — Agent Notes

Conventions and decisions that are easy to get wrong without context. See
[TODO.md](TODO.md) for status, [SPEC.md](SPEC.md) for scope, and `git issue list`
for the tracker (`.ba/` is not initialized here).

## Prefer OpenCode APIs over reading config files

When the app needs OpenCode state — config, skills, commands, MCP servers,
models — query the running server's HTTP API instead of scanning or parsing
config files ourselves:

- `GET /config` — effective merged config (model, `mcp`, `plugin`, …)
- `GET /skill` — resolved skills (name, description, location)
- `GET /command` — resolved commands; entries with `source: "skill"` are
  mirrors of skills, filter them out when listing commands
- `GET /mcp` — live MCP server status (`connected` / `failed` + error)
- `GET /provider` — providers, models, connection status
- All workspace-scoped requests take a `?directory=<workspace>` query.

Why: OpenCode already resolves overlapping config files (`config.json`,
`opencode.json`, JSONC variants, project vs global, built-ins). Re-implementing
that resolution locally caused duplicate inventory entries (`#996e90c`), and
the API exposes state files cannot, such as live MCP connection status
(`#15b1696`). Local file scanning (`WorkspaceInventoryService`) is kept only as
a fallback for before the runtime is healthy.

Config writes follow the same rule: use the config API, not file edits. Note
that `PATCH /config` writes a workspace `config.json` that `GET /config` does
not reread in current builds — use `PATCH /global/config` for the effective
default model (`#300151e`).

## Build, test, verify

- `mask build` / `mask test` (the test task carries the swift-testing linker
  flags needed with the CommandLineTools toolchain — plain `swift test` fails
  with "no such module 'Testing'").
- Live API shapes can be probed against a running server: find listeners with
  `lsof -iTCP -sTCP:LISTEN | grep opencode`, then curl with `?directory=`.
