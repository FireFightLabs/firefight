# MCP Server

Firefight ships a read-only [Model Context Protocol](https://modelcontextprotocol.io) server at `POST /mcp`, so any MCP client — Claude Code, Cursor, or your own agents — can query incidents, alerts, the service catalog, and dry-run alert routing.

## Connecting

Mint a token under **Settings → API keys**:

- **Personal token** ("acts as you") — reads everything you can see. For your own agent sessions.
- **Service key** with read scopes (`incidents`, `alerts`, `catalog`, `policies`) — for headless agents and CI.

**Claude Code**

```sh
claude mcp add --transport http firefight https://<your-host>/mcp \
  --header "Authorization: Bearer ff_..."
```

**Cursor** (`.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "firefight": {
      "url": "https://<your-host>/mcp",
      "headers": { "Authorization": "Bearer ff_..." }
    }
  }
}
```

Any other client: Streamable HTTP transport, `Authorization: Bearer` header. OAuth-based connect (browser consent, claude.ai web connectors) is planned; header tokens remain the automation path.

## Tools (all read-only)

| Tool | Answers |
|---|---|
| `search_incidents` | "What's open? What resolved this week?" — filters: status, severity, stage, text, time range |
| `get_incident` | "Tell me everything about INC-42" — detail, timeline, postmortem state, attached alerts |
| `search_alerts` | "What's firing and how did it route?" — source, routing state, matched rule, incident link |
| `search_catalog` | "Who owns checkout?" — entries, attributes, relationships |
| `evaluate_routing` | "If this alert arrived, what would happen?" — matched rule, outcome, per-condition trace |

Results are workspace-scoped to the token, capped at 50 items with explicit `truncated` markers, and returned as structured JSON.

## Architecture

`McpController` (entry point: Bearer auth → `Current.principal`, API rate limit, stateless `handle_json` dispatch — no sessions/SSE, multi-worker safe) → `Mcp::ToolDispatcher` (per-tool resource permission check, telemetry — the single seam the future Ability Gateway wraps) → tool classes in `app/mcp/` (workspace-scoped reads + formatting only; no business logic, no writes, no adapter calls; tool names from `Mcp::Tools` constants).

Personal tokens pass all tools; service keys need `<resource>:read` per tool (`search_incidents`/`get_incident` → `incidents`, `search_alerts` → `alerts`, `search_catalog` → `catalog`, `evaluate_routing` → `policies`).
