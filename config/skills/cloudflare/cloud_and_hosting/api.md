---
name: cloudflare_api
when: A question about Cloudflare that the other Cloudflare skills do not answer, such as the account's audit log, API tokens, members, certificates, Workers and their deployments, Pages deployments, tunnels, load balancers, firewall events or billing, and finding the path of any read of Cloudflare's API
tools: [execute, search, get_resource_map, resource_status]
references: [api/limits.md]
---
`execute` reads Cloudflare's API without asking the person when it is given `method` GET, a `path` and its `query`, and no code, since Firefight writes that request itself. Code is only for a change, which asks first.

1. Find the zone or account a read is about on the resource map with `get_resource_map` first. It names the account id and the zone id the paths take, and `resource_status` with the domain reads the zone where the map is not yours to read.
2. Take the path from the key reads below when one fits. For any other read, find its endpoint with `search` against Cloudflare's API specification before calling it, rather than writing a path from memory. When neither has a read for the question, Cloudflare's API does not offer it. Say so, and give the steps in Cloudflare's dashboard instead.
3. Put every parameter in `query`, never in the path. A list answers one page: pass per_page and page, or the cursor it answered, for the next.
4. A read Cloudflare refuses for a missing permission names it. Say which, and that the person grants it by connecting Cloudflare again and picking it on Cloudflare's consent screen.
5. A tunnel's token, a KV value and an R2 object are never read. Read the tunnel, the namespace's keys or the bucket's object names instead.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /accounts/{account_id}/audit_logs (since, before, action.type, actor.email, zone.name, per_page, page): The account's audit log, who changed what and when, newest first.
- GET /user/tokens (include_expired, per_page, page): The person's API tokens by name, status, policies and expiry, never their values.
- GET /accounts/{account_id}/tokens (include_expired, per_page, page): The account's API tokens by name, status, policies and expiry, never their values.
- GET /accounts/{account_id}/members (status, per_page, page): The account's members, their roles and status.
- GET /zones (name, status, account.id, per_page, page): The zones the connection reaches, with each one's status, plan and name servers.
- GET /zones/{zone_id}: One zone, with its status, plan, name servers and whether it is paused.
- GET /zones/{zone_id}/settings: Every setting of a zone, such as SSL mode, caching, HTTP/3 and security level.
- GET /zones/{zone_id}/settings/{setting_id}: One zone setting, such as ssl or always_use_https, and when it changed.
- GET /zones/{zone_id}/dns_records (name, type, content, proxied, per_page, page): A zone's DNS records, narrowed by name, type or content, and whether each is proxied.
- GET /zones/{zone_id}/dnssec: Whether DNSSEC is on for a zone and its DS record.
- GET /zones/{zone_id}/ssl/certificate_packs (status, per_page, page): A zone's certificate packs, with their hosts, status and expiry.
- GET /zones/{zone_id}/ssl/certificate_packs/{certificate_pack_id}: One certificate pack, with its hosts, authority, validation and expiry.
- GET /zones/{zone_id}/ssl/universal/settings: Whether Universal SSL is on for a zone.
- GET /zones/{zone_id}/ssl/verification: The validation status of a zone's certificates.
- GET /zones/{zone_id}/custom_hostnames (hostname, ssl_status, per_page, page): A zone's custom hostnames, with their SSL and ownership status.
- GET /accounts/{account_id}/workers/scripts: The account's Workers, with when each was changed.
- GET /accounts/{account_id}/workers/scripts/{script_name}/settings: A Worker's settings, such as its bindings, compatibility date and logging.
- GET /accounts/{account_id}/workers/scripts/{script_name}/deployments: A Worker's deployments, newest first, with the versions each sent traffic to.
- GET /accounts/{account_id}/workers/scripts/{script_name}/versions (deployable, per_page, page): A Worker's versions, with who made each and when.
- GET /accounts/{account_id}/workers/scripts/{script_name}/versions/{version_id}: One version of a Worker, with its bindings and how it was made.
- GET /accounts/{account_id}/workers/scripts/{script_name}/schedules: A Worker's cron triggers.
- GET /accounts/{account_id}/workers/domains (zone_name, service, hostname): The custom domains Workers answer on, narrowed by zone, Worker or hostname.
- GET /accounts/{account_id}/workers/observability/issues (service, status, search, page, perPage): Errors Workers Observability detected, narrowed by Worker or status.
- GET /accounts/{account_id}/pages/projects (per_page, page): The account's Pages projects, with each one's latest deployment.
- GET /accounts/{account_id}/pages/projects/{project_name}/deployments (env, per_page, page): A Pages project's deployments, newest first, with each one's status and commit.
- GET /accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}: One Pages deployment, with its stages, commit and status.
- GET /accounts/{account_id}/pages/projects/{project_name}/deployments/{deployment_id}/history/logs: A Pages deployment's build log.
- GET /accounts/{account_id}/cfd_tunnel (name, status, is_deleted, per_page, page): The account's tunnels, with each one's status and connections, never a token.
- GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/connections: A tunnel's connectors, their versions and the data centres they reach.
- GET /zones/{zone_id}/load_balancers: A zone's load balancers, with their pools, steering and whether each is on.
- GET /accounts/{account_id}/load_balancers/pools (monitor): The account's load balancer pools, their origins and monitor.
- GET /accounts/{account_id}/load_balancers/pools/{pool_id}/health: A pool's health, each origin's state as seen from each region.
- GET /accounts/{account_id}/load_balancers/monitors: The account's load balancer monitors, what each checks and how often.
- GET /zones/{zone_id}/healthchecks (per_page, page): A zone's standalone health checks and each one's status.
- GET /zones/{zone_id}/rulesets (per_page, cursor): A zone's rulesets, such as WAF, custom rules and rate limiting, by phase.
- GET /zones/{zone_id}/rulesets/phases/{ruleset_phase}/entrypoint: The rules a zone runs in one phase, such as http_request_firewall_custom.
- GET /zones/{zone_id}/rate_limits (per_page, page): A zone's older rate limits, what each matches and does.
- GET /zones/{zone_id}/pagerules (status): A zone's page rules, in order, with their actions and status.
- GET /accounts/{account_id}/alerting/v3/history (since, before, per_page, page): Notifications Cloudflare sent the account, such as health check or DDoS alerts.
- GET /accounts/{account_id}/subscriptions: The account's subscriptions, with each one's plan, price and state.
