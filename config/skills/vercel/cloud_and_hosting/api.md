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
