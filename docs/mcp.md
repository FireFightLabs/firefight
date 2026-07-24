# MCP Server

Firefight ships a read-only [Model Context Protocol](https://modelcontextprotocol.io) server at `POST /mcp`, so any MCP client — Claude Code, Cursor, or your own agents — can query incidents, alerts, the service catalog, runbooks, and dry-run alert routing.

## Connecting

Mint a token under **Settings → API keys**:

- **Personal token** ("acts as you") — reads everything you can see. For your own agent sessions.
- **Service key** with read scopes (`incidents`, `alerts`, `catalog`, `policies`) — for headless agents and CI.

**Claude Code (OAuth — recommended)**

```sh
claude mcp add --transport http firefight https://<your-host>/mcp
```

On first use your browser opens Firefight's consent screen ("<client> wants read-only access to <workspace> as <you>") — click Authorize and you're connected. The client self-registers via dynamic client registration; tokens are short-lived with refresh rotation, PKCE (S256) is required, and you can revoke any connection under **Settings → API keys → Connected agents**.

**Claude Code (header token — for automation)**

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

Any other client: Streamable HTTP transport with either OAuth (discovery via `/.well-known/oauth-protected-resource`, RFC 7591 registration, PKCE required) or an `Authorization: Bearer` header token. Headless agents and CI should use header tokens — machines can't click consent screens.

## Tools (all read-only)

| Tool | Answers |
|---|---|
| `search_incidents` | "What's open? What resolved this week?" — filters: status, severity, stage, text, time range |
| `get_incident` | "Tell me everything about INC-42" — detail, timeline, postmortem state, attached alerts |
| `search_alerts` | "What's firing and how did it route?" — source, routing state, matched rule, incident link |
| `search_catalog` | "Who owns checkout?" — entries, attributes, relationships |
| `evaluate_routing` | "If this alert arrived, what would happen?" — matched rule, outcome, per-condition trace |
| `search_runbooks` | "Is there a runbook for this?" — incident response procedures by name/summary |
| `get_runbook` | "Walk me through the DB failover runbook" — full content and ordered steps |

Results are workspace-scoped to the token, capped at 50 items with explicit `truncated` markers, and returned as structured JSON.

The server is self-describing for agents: server instructions, tool descriptions, and guidance-worthy responses (permission errors, no routing policy, unmatched dry runs) link to the relevant public docs page via `Mcp::Docs` constants — each page is fetchable as raw markdown (`https://firefight.app/docs/**/*.md`, index at `/llms.txt`).

## Architecture

`McpController` (entry point: Bearer auth → `Current.principal`, API rate limit, stateless `handle_json` dispatch — no sessions/SSE, multi-worker safe) → `Mcp::ToolDispatcher` (per-tool resource permission check, telemetry — the single seam the future Ability Gateway wraps) → tool classes in `app/mcp/` (workspace-scoped reads + formatting only; no business logic, no writes, no adapter calls; tool names from `Mcp::Tools` constants).

Personal tokens pass all tools; service keys need `<resource>:read` per tool (`search_incidents`/`get_incident` → `incidents`, `search_alerts` → `alerts`, `search_catalog` → `catalog`, `evaluate_routing` → `policies`, `search_runbooks`/`get_runbook` → `runbooks`).
