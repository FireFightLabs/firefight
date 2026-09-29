---
description: Connect to Cloudflare's managed remote MCP servers to read configurations, manage services, and automate actions across your account.
title: Cloudflare's own MCP servers
image: https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/og.png?v=2698c333db6912a5
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/agents/llms.txt  
> Use this file to discover all available pages before exploring further.

# Cloudflare's own MCP servers

Last updated Jul 28, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Cloudflare runs a catalog of managed remote MCP servers which you can connect to using OAuth on clients like [Claude ↗︎](https://modelcontextprotocol.io/quickstart/user), [Windsurf ↗︎](https://docs.windsurf.com/windsurf/cascade/mcp), our own [AI Playground ↗︎](https://playground.ai.cloudflare.com/) or any [SDK that supports MCP ↗︎](https://github.com/cloudflare/agents/tree/main/packages/agents/src/mcp).

These MCP servers allow your MCP client to read configurations from your account, process information, make suggestions based on data, and even make those suggested changes for you. All of these actions can happen across Cloudflare's many services including application development, security and performance.

Use the Streamable HTTP endpoint at `/mcp` for new connections. The servers support the new MCP 2026-07-28 Specification and stateless requests from 2025 Streamable HTTP clients. Historical `/sse` URLs remain available as aliases for the same Streamable HTTP handler, but they do not serve the deprecated HTTP+SSE transport. Clients configured to force SSE transport must switch to Streamable HTTP or automatic transport detection.

## Cloudflare API MCP server

The [Cloudflare API MCP server ↗︎](https://github.com/cloudflare/mcp) provides access to the entire [Cloudflare API](https://developers.cloudflare.com/api/) — over 2,500 endpoints across DNS, Workers, R2, Zero Trust, and every other product — through just two tools: `search()` and `execute()`.

It uses [the search-and-execute Code Mode pattern](https://developers.cloudflare.com/agents/model-context-protocol/codemode/#search-and-execute), a technique where the model writes JavaScript against a typed representation of the OpenAPI spec and the Cloudflare API client, rather than loading individual tool definitions for each endpoint. The generated code runs inside an isolated [Dynamic Worker](https://developers.cloudflare.com/workers/runtime-apis/bindings/worker-loader/) sandbox.

This approach uses approximately 1,000 tokens regardless of how many API endpoints exist. An equivalent MCP server that exposed every endpoint as a native tool would consume over 1 million tokens — more than the entire context window of most foundation models.

| Approach | Tools | Token cost |
| --- | --- | --- |
| Native MCP (full schemas) | 2,594 | \~1,170,000 |
| Native MCP (required params only) | 2,594 | \~244,000 |
| Code Mode | 2 | \~1,000 |

### Connect to the Cloudflare API MCP server

Add the following configuration to your MCP client:

```json
{
	"mcpServers": {
		"cloudflare-api": {
			"url": "https://mcp.cloudflare.com/mcp"
		}
	}
}
```

When you connect, you will be redirected to Cloudflare to authorize via OAuth and select the permissions to grant to your agent.

For CI/CD or automation, you can create a [Cloudflare API token ↗︎](https://dash.cloudflare.com/profile/api-tokens) with the permissions you need and pass it as a bearer token in the `Authorization` header. Both user tokens and account tokens are supported.

For more information, refer to the [Cloudflare MCP repository ↗︎](https://github.com/cloudflare/mcp).

### Install via agent and IDE plugins

You can install the [Cloudflare Skills plugin ↗︎](https://github.com/cloudflare/skills), which bundles the Cloudflare MCP servers alongside contextual skills and slash commands for building on Cloudflare. The plugin works with any agent that supports the Agent Skills standard, including Claude Code, OpenCode, OpenAI Codex, and Pi.

#### Claude Code

Install using the [plugin marketplace ↗︎](https://code.claude.com/docs/en/discover-plugins#add-from-github):

```txt
/plugin marketplace add cloudflare/skills
```

#### Cursor

Install from the **Cursor Marketplace**, or add manually via **Settings** > **Rules** > **Add Rule** > **Remote Rule (Github)** with `cloudflare/skills`.

#### npx skills

Install using the [`npx skills` ↗︎](https://skills.sh) CLI:

```sh
npx skills add https://github.com/cloudflare/skills
```

#### Clone or copy

Clone the [cloudflare/skills ↗︎](https://github.com/cloudflare/skills) repository and copy the skill folders into the appropriate directory for your agent:

| Agent | Skill directory | Docs |
| --- | --- | --- |
| Claude Code | `~/.claude/skills/` | [Claude Code skills ↗︎](https://code.claude.com/docs/en/skills) |
| Cursor | `~/.cursor/skills/` | [Cursor skills ↗︎](https://cursor.com/docs/context/skills) |
| OpenCode | `~/.config/opencode/skills/` | [OpenCode skills ↗︎](https://opencode.ai/docs/skills/) |
| OpenAI Codex | `~/.codex/skills/` | [OpenAI Codex skills ↗︎](https://developers.openai.com/codex/skills/) |
| Pi | `~/.pi/agent/skills/` | [Pi coding agent skills ↗︎](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#skills) |

## Product-specific MCP servers

In addition to the Cloudflare API MCP server, Cloudflare provides product-specific MCP servers for targeted use cases:

| Server Name | Description | Server URL |
| --- | --- | --- |
| [Documentation server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/docs-ai-search) | Get up to date reference information on Cloudflare | `https://docs.mcp.cloudflare.com/mcp` |
| [Workers Bindings server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/workers-bindings) | Build Workers applications with storage, AI, and compute primitives | `https://bindings.mcp.cloudflare.com/mcp` |
| [Workers Builds server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/workers-builds) | Get insights and manage your Cloudflare Workers Builds | `https://builds.mcp.cloudflare.com/mcp` |
| [Observability server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/workers-observability) | Debug and get insight into your application's logs and analytics | `https://observability.mcp.cloudflare.com/mcp` |
| [Radar server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/radar) | Get global Internet traffic insights, trends, URL scans, and other utilities | `https://radar.mcp.cloudflare.com/mcp` |
| [Container server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/sandbox-container) | Spin up a sandbox development environment | `https://containers.mcp.cloudflare.com/mcp` |
| [Browser Run server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/browser-rendering) | Fetch web pages, convert them to markdown and take screenshots | `https://browser.mcp.cloudflare.com/mcp` |
| [Logpush server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/logpush) | Get quick summaries for Logpush job health | `https://logs.mcp.cloudflare.com/mcp` |
| [AI Gateway server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/ai-gateway) | Search your logs, get details about the prompts and responses | `https://ai-gateway.mcp.cloudflare.com/mcp` |
| [AI Search server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/autorag) | List and search documents on your AI Searches | `https://autorag.mcp.cloudflare.com/mcp` |
| [Audit Logs server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/auditlogs) | Query audit logs and generate reports for review | `https://auditlogs.mcp.cloudflare.com/mcp` |
| [DNS Analytics server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/dns-analytics) | Optimize DNS performance and debug issues based on current set up | `https://dns-analytics.mcp.cloudflare.com/mcp` |
| [Digital Experience Monitoring server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/dex-analysis) | Get quick insight on critical applications for your organization | `https://dex.mcp.cloudflare.com/mcp` |
| [Cloudflare One CASB server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/cloudflare-one-casb) | Quickly identify any security misconfigurations for SaaS applications to safeguard users & data | `https://casb.mcp.cloudflare.com/mcp` |
| [GraphQL server ↗︎](https://github.com/cloudflare/mcp-server-cloudflare/tree/main/apps/graphql/) | Get analytics data using Cloudflare's GraphQL API | `https://graphql.mcp.cloudflare.com/mcp` |
| [Agents SDK Documentation server ↗︎](https://github.com/cloudflare/agents/tree/main/site/agents) | Token-efficient search of the Cloudflare Agents SDK documentation | `https://agents.cloudflare.com/mcp` |

Check the [GitHub page ↗︎](https://github.com/cloudflare/mcp-server-cloudflare) to learn how to use Cloudflare's remote MCP servers with different MCP clients.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/#page","headline":"Cloudflare's own MCP servers","description":"Connect to Cloudflare's managed remote MCP servers to read configurations, manage services, and automate actions across your account.","url":"https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/","inLanguage":"en","image":"https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/og.png?v=2698c333db6912a5","dateModified":"2026-07-28","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"},"keywords":["MCP"]}
```
