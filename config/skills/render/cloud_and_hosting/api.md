---
name: render_api
when: A question about Render that the other Render tools do not answer, such as a service's jobs, disks, custom domains, environment groups, blueprints, projects, one deploy by its id, or anything else Render's API reads, and finding out whether Render's API offers a read at all
tools: [api_read, list_resources]
---
`api_read` sends a GET to any path of Render's public API and answers what Render said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the restart, rollback and scale tools in render_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is there. Reach for `api_read` for the rest.
2. Find the path in Render's API reference before the first call, not by guessing. Render publishes it at https://api-docs.render.com/reference, with every read listed by area. Read it with the web reading tool, where the workspace allows reading the web. Render's reference is not copied into Firefight's documentation, so search_docs does not hold it. When the reference lists no read for the question, Render's API does not offer it. Say so, and give the steps in Render's dashboard instead.
3. Fill the path's ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass limit, at most 100, and to read on, pass the cursor of the last item it answered as cursor. Pass ownerId to keep a list to this connection's workspace, since a list naming another workspace is refused.
5. Environment variables, secret files and registry credentials come back as their names, with values hidden. A datastore's connection info and a Postgres export are never read. When the question needs a value, say which variable to check in Render.
