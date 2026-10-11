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

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /v0/jobs (kind, status, pipe_name, created_after, created_before): The last 100 jobs of the past 48 hours, such as imports, copies and populates, with their status.
- GET /v0/jobs/{job_id}: One job, with its kind, status, data source, timing and the error when it failed.
- GET /v0/datasources: The workspace's data sources, with each one's engine and when it changed.
- GET /v0/datasources/{name}: One data source, with its schema, engine, row count, size and the pipes that use it.
- GET /v0/pipes: The workspace's pipes, with their nodes and which one is published as an endpoint.
- GET /v0/pipes/{name}: One pipe, with each node's SQL and whether it is an endpoint, copy or materialized view.
- GET /v0/pipes/{name}/explain: The query plan of a pipe's main node, with its parameters, to see why it is slow.
- GET /v0/pipes/{name}/nodes/{node_name}/explain: The query plan of one node of a pipe, with its parameters.
- GET /v0/pipes/{name}.json (q): What an endpoint answers now with its parameters, with the rows read and time taken.
- GET /v0/sql (q): A SELECT over data sources, pipes and service data sources such as tinybird.pipe_stats_rt.
- GET /v0/tokens: The workspace's static tokens by name and scope, never their values.
- GET /v0/variables: The workspace's environment variables by name, never their values.
- GET /v0/organizations/{organization_id}/members: The organization's members and their roles.
- GET /v0/organizations/{organization_id}/clusters: The organization's dedicated clusters, with their replicas, weights and operations in progress.
