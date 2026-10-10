---
name: tinybird_api
when: A question about Tinybird that the other Tinybird tools do not answer, such as one job by its id, a data source's details, a pipe's nodes, or anything else Tinybird's API reads, and finding out whether the API offers a read at all
tools: [api_read, list_datasources, list_endpoints, jobs]
---
`api_read` sends a GET to any path of Tinybird's API for this workspace and answers what Tinybird said. It only reads, so it never needs the person's go ahead and works while investigating and watching.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_datasources`, `list_endpoints` and `jobs`. Reach for `api_read` for the rest.
2. Find the path in Tinybird's API reference before the first call, not by guessing. Tinybird publishes it at https://www.tinybird.co/docs/api-reference, with a page for each API: Data Sources, Pipes, Query, Jobs, Tokens, Events, Environment Variables and Analyze. Read it with the web reading tool, where the workspace allows reading the web. Tinybird publishes no description of its API that Firefight's documentation could hold, so search_docs does not hold it. When the reference lists no read for the question, the API does not offer it. Say so.
3. Paths start /v0 or /v1, as the reference writes them, and every parameter goes in `query`, never in the path.
4. Tokens, environment variables and the credentials of connections come back as their names. When Tinybird refuses a read, the token lacks the scope for it, so say which scope the token needs.
