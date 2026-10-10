---
name: railway_api
when: A question about Railway that the other Railway tools do not answer, such as a project's environments and services, one deployment by its id, volumes and their backups, domains, TCP proxies, deployment triggers or the workspace's members, and finding out whether Railway's API offers a read at all
tools: [api_read, list_resources]
references: [api/index.md]
---
`api_read` runs one GraphQL query against Railway's public API and answers what Railway said. It only reads, so it never needs the person's go ahead and works while investigating and watching. A mutation or a subscription is refused. Changes go through the restart, rollback and scale in railway_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for the services, databases and cron jobs. Reach for `api_read` for the rest.
2. Find the fields in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every query field Railway's API offers by area, then the area's page it names for the arguments each takes. When the reference lists no field for the question, Railway's API does not offer it. Say so, and give the steps in Railway's dashboard instead.
3. Write the `query` with its values as GraphQL variables, such as query($id: String!) { project(id: $id) { name } }, and pass them in `variables`. Name ids from `list_resources` or an earlier answer. Reads stay in the projects this connection reads, so name the project, and a query reaching another one is refused.
4. A list is a connection. Pass first, and to read on, pass the pageInfo's endCursor as after.
5. A query that reads variables, an environment's config or tokens comes back as names only, with every value hidden. When the question needs a value, say which variable to check in Railway.
