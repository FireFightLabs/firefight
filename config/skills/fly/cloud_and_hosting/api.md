---
name: fly_api
when: A question about Fly.io that the other Fly.io tools do not answer, such as one machine and its events, processes and versions, an app's volumes and snapshots, IP assignments and certificates, or a Managed Postgres cluster's databases, backups and active or slow queries, and finding out whether Fly.io's Machines API offers a read at all
tools: [api_read, list_resources]
references: [api/index.md]
---
`api_read` sends a GET to any path of Fly.io's Machines API and answers what Fly.io said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the restart and rollback in fly_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for the apps and clusters. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read the Machines API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start with /v1, such as /v1/apps/<app>/machines. When the reference lists no read for the question, the Machines API does not offer it. Releases are read with the deploy tools, and anything else only flyctl or the dashboard shows is a step for a person.
3. Fill the path's app names and ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path. Reads stay in this connection's organization, so an app or cluster of another one is refused.
4. A list answers one page. Pass limit, and to read on, pass the next_cursor it answered as cursor.
5. Secrets and machine environments come back as their names, with values hidden, and show_secrets is never sent. A Postgres user's credentials and a machine's lease are never read, and neither is a machine's wait, so read the machine itself for its state.
