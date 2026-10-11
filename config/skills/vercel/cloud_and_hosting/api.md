---
name: vercel_api
when: A question about Vercel that the other Vercel tools do not answer, such as a project's settings, domains and their configuration, aliases, one deployment by its id and its files, checks, firewall settings, Edge Config or the team's members, and finding out whether Vercel's API offers a read at all
tools: [api_read, list_resources]
references: [api/index.md]
---
`api_read` sends a GET to any path of Vercel's REST API and answers what Vercel said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback and promotion in vercel_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for the projects. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read Vercel's API offers by area, then the area's page it names for the parameters and the fields each read answers. Write the path with its version, as the reference does, such as /v9/projects/<project>/domains. When the reference lists no read for the question, Vercel's API does not offer it. Say so, and give the steps in Vercel's dashboard instead.
3. Fill the path's ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path. The team is always this connection's, so leave teamId and slug out.
4. A list answers one page. Pass limit, and to read on, pass the pagination's next as until.
5. Environment variables, log drains, drains and tokens come back as their names, with values hidden, and decrypt is never sent. A deploy hook's address and a project's protection bypass are hidden too. When the question needs a value, say which variable to check in Vercel.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /v7/deployments (projectId, target, state, branch, sha, since, until, limit): Deployments, newest first, with each one's state, target, branch and commit.
- GET /v13/deployments/{idOrUrl}: One deployment, with its state, error, commit, target and aliases.
- GET /v3/deployments/{idOrUrl}/events (direction, limit, since, until, statusCode): A deployment's build log lines, in order, to see why a build failed.
- GET /v1/projects/{projectId}/deployments/{deploymentId}/runtime-logs: A deployment's function and request logs, with status codes and errors.
- GET /v1/deployments/{deploymentId}/checks: The checks run against a deployment, with each one's status and conclusion.
- GET /v2/deployments/{id}/aliases: The domains and aliases a deployment serves.
- GET /v10/projects (search, limit, from): The team's projects, with each one's framework and latest deployments.
- GET /v9/projects/{idOrName}: One project, with its settings, framework, repository and production deployment.
- GET /v9/projects/{idOrName}/domains (production, verified, limit): A project's domains, with each one's branch, redirect and verification.
- GET /v1/projects/{idOrName}/rolling-release (state): A project's active rolling release, with its stage and traffic share.
- GET /v1/projects/{idOrName}/rolling-release/config: How a project's rolling releases are set up, stage by stage.
- GET /v1/projects/{projectId}/promote/aliases (limit, since, until): The aliases of a promotion in progress, with each one's status.
- GET /v9/projects/{idOrName}/custom-environments: A project's custom environments, with their branches and domains.
- GET /v10/projects/{idOrName}/env: A project's environment variables, by name and target, never their values.
- GET /v1/env: The team's shared environment variables, by name, never their values.
- GET /v1/projects/{idOrName}/members (limit, since, until): A project's members and their roles.
- GET /v3/events (types, projectIds, since, until, limit): The team's activity log, such as deploys, setting changes and member changes, newest first.
- GET /v2/teams/{teamId}: One team, with its plan and settings.
- GET /v3/teams/{teamId}/members (role, search, limit): The team's members, with their roles and when they joined.
- GET /v1/access-groups (limit): The team's access groups and the roles they grant.
- GET /v6/user/tokens: The user's tokens, by name, scope and expiry, never their values.
- GET /v5/domains (limit, since, until): The team's domains, with who serves their DNS and whether each is verified.
- GET /v5/domains/{domain}: One domain, with its nameservers, verification and expiry.
- GET /v6/domains/{domain}/config: Whether a domain is set up to point at Vercel, and what is wrong if not.
- GET /v5/domains/{domain}/records (limit, since, until): A domain's DNS records held at Vercel.
- GET /v8/certs: The team's TLS certificates, with their domains and expiry.
- GET /v8/certs/{id}: One certificate, with its domains, issuer and expiry.
- GET /v4/aliases (projectId, domain, limit): Every alias, with the deployment each points at.
- GET /v1/security/firewall/config: A project's active firewall rules and managed rule sets.
- GET /v1/security/firewall/attack-status (projectId, since): Whether a project is under attack now, and what is being blocked.
- GET /v1/security/firewall/events (projectId, startTimestamp, endTimestamp, action, limit, cursor): What the firewall blocked or challenged for a project, over time.
- GET /v1/drains (projectId): Where logs and traces are sent, by name and type, never their keys.
- GET /v1/webhooks (projectId): The team's webhooks, with the events each sends and where.
- GET /v1/global-config: The team's Edge Configs, with their size and last change.
- GET /v1/global-config/{edgeConfigId}/backups (limit): An Edge Config's earlier versions, newest first, to see what changed.
- GET /v1/billing/charges (from, to): The team's charges by service over a time range.
- GET /v1/connect/networks: The team's Secure Compute networks, with their region and status.
