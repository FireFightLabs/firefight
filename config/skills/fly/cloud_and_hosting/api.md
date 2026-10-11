---
name: fly_api
when: A question about Fly.io that the other Fly.io tools do not answer, such as one machine and its events, processes and versions, an app's volumes and snapshots, IP assignments and certificates, or a Managed Postgres cluster's databases, backups and active or slow queries, a release older than the newest few through Fly.io's GraphQL API, and finding out whether Fly.io's Machines API offers a read at all
tools: [api_read, graphql_read, list_resources]
references: [api/index.md]
---
`api_read` sends a GET to any path of Fly.io's Machines API and answers what Fly.io said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the restart and rollback in fly_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for the apps and clusters. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read the Machines API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start with /v1, such as /v1/apps/<app>/machines. When the reference lists no read for the question, the Machines API does not offer it. Releases are read with the deploy tools, and those past the newest with `graphql_read`. Anything else only flyctl or the dashboard shows is a step for a person.
3. Fill the path's app names and ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path. Reads stay in this connection's organization, so an app or cluster of another one is refused.
4. A list answers one page. Pass limit, and to read on, pass the next_cursor it answered as cursor.
5. `graphql_read` runs one GraphQL query that starts from app(name: ...) or organization(slug: ...) in this connection's organization, such as { app(name: "web") { releasesUnprocessed(first: 50) { nodes { id version status reason createdAt } pageInfo { hasNextPage endCursor } } } }. A list is a connection: pass first, and the pageInfo's endCursor as after for the next page. A mutation is never sent.
6. Secrets and machine environments come back as their names, with values hidden, and show_secrets is never sent. A GraphQL query that reads secrets, tokens, keys or config answers names only. A Postgres user's credentials and a machine's lease are never read, and neither is a machine's wait, so read the machine itself for its state.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /v1/apps (org_slug, limit, cursor): The organization's apps, with each one's machine count and network.
- GET /v1/apps/{app_name}: One app, with its organization, network and status.
- GET /v1/apps/{app_name}/machines (state, cursor, limit): The app's machines, each with its state, region, image and when it last changed.
- GET /v1/apps/{app_name}/machines/{machine_id}: One machine, with its state, config, image, region and checks.
- GET /v1/apps/{app_name}/machines/{machine_id}/events (limit): A machine's recent events, such as starts, stops, exits and restarts, with exit codes.
- GET /v1/apps/{app_name}/machines/{machine_id}/versions: A machine's earlier config versions, newest first, to see what a deploy changed.
- GET /v1/apps/{app_name}/machines/{machine_id}/ps: The processes running inside a machine, with their CPU and memory.
- GET /v1/apps/{app_name}/machines/{machine_id}/memory: A machine's memory limit and how much is in use.
- GET /v1/apps/{app_name}/machines/{machine_id}/metadata: A machine's metadata labels, such as its process group and release.
- GET /v1/orgs/{org_slug}/machines (state, cursor, limit): Every machine across the organization's apps, to find one by state or region.
- GET /v1/apps/{app_name}/ip_assignments: The app's public and private IP addresses, with their regions.
- GET /v1/apps/{app_name}/certificates (filter, cursor, limit): The app's TLS certificates by hostname, with each one's status.
- GET /v1/apps/{app_name}/certificates/{hostname}: One hostname's certificate, with its issue status, DNS checks and expiry.
- GET /v1/apps/{app_name}/volumes (cursor, limit): The app's volumes, with size, region, state and the machine each is attached to.
- GET /v1/apps/{app_name}/volumes/{volume_id}: One volume, with its size, state, encryption and attached machine.
- GET /v1/apps/{app_name}/volumes/{volume_id}/snapshots: A volume's snapshots, with when each was taken and its size.
- GET /v1/orgs/{org_slug}/volumes (state, cursor, limit): Every volume across the organization's apps.
- GET /v1/apps/{app_name}/secrets: The app's secrets, by name and when each was set, never their values.
- GET /v1/apps/{app_name}/secretkeys: The app's secret keys, by name and type, never their values.
- GET /v1/postgres (org_slug): The organization's Managed Postgres clusters, with their status and region.
- GET /v1/postgres/{postgres_cluster_id}: One Managed Postgres cluster, with its status, plan, region and replicas.
- GET /v1/postgres/{postgres_cluster_id}/backups: A Postgres cluster's backups, with when each was taken.
- GET /v1/postgres/{postgres_cluster_id}/queries/active (database): Queries running now on a Postgres cluster, with how long each has run.
- GET /v1/postgres/{postgres_cluster_id}/queries/slow: The slowest queries on a Postgres cluster, with their time and call count.
- GET /v1/postgres/{postgres_cluster_id}/databases: The databases on a Postgres cluster.
- GET /v1/postgres/{postgres_cluster_id}/users: The users on a Postgres cluster, by name and role.
- GET /v1/platform/regions: Fly.io's regions, with each one's code and whether it takes new machines.
- GET /v1/tokens/current: What the connection's own token can reach, by name, never its value.
