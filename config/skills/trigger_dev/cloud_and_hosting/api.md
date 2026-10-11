---
name: trigger_dev_api
when: A question about Trigger.dev that the other Trigger.dev tools do not answer, such as one deployment or batch, a run's result or attempts, schedules, waitpoints, bulk actions or concurrency limits, or anything else Trigger.dev's API reads, and finding out whether the API offers a read at all
tools: [api_read, list_tasks, list_runs]
references: [api/index.md]
---
`api_read` sends a GET to any path of Trigger.dev's management API for this environment and answers what Trigger.dev said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Promoting a version goes through its own tool, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_tasks` for what is deployed, `list_runs` for runs. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read the API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start /api, as the reference writes them. When the reference lists no read for the question, the API does not offer it. Say so, and give the steps in Trigger.dev's dashboard instead.
3. Put every parameter in `query`, never in the path, with the names the reference gives, such as page[size].
4. A list answers one page. To read on, pass page[after] set to the next the answer's pagination gave.
5. Environment variables come back as their names, with values hidden. When the key's preset cannot make a read, say which preset to give the key in Trigger.dev.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /api/v1/runs (page, filter): Runs in the environment, newest first, filtered by status, task, version or time.
- GET /api/v1/projects/{projectRef}/runs (page, filter): Runs across every environment of a project, filtered by status, task or time.
- GET /api/v3/runs/{runId}: One run, with its status, attempts, error, task, version and timings.
- GET /api/v1/runs/{runId}/events: A run's events in order, such as attempts, retries, waits and failures.
- GET /api/v1/runs/{runId}/result: A finished run's output or the error it ended with.
- GET /api/v1/errors (page, filter): The environment's error groups, with how often each happened and when last.
- GET /api/v1/errors/{errorId}: One error group, with its message, stack, affected tasks and counts.
- GET /api/v1/deployments (status, period, from, to): The environment's deployments, newest first, with their status and version.
- GET /api/v1/deployments/latest: The newest deployment, with its status, version and any error.
- GET /api/v1/deployments/{deploymentId}: One deployment, with its status, version, tasks and any build error.
- GET /api/v1/queues (page, perPage): The environment's queues, with how many runs are queued and running and their limits.
- GET /api/v1/queues/{queueParam} (type): One queue, with its queued and running counts, limit and whether it is paused.
- GET /api/v1/concurrency-limits (page, perPage): The environment's concurrency limits.
- GET /api/v1/concurrency-limits/{name}: One concurrency limit and how much of it is in use.
- GET /api/v1/runs/{runId}/trace (page[size]): A run's trace, its spans and how long each took.
- GET /api/v1/batches/{batchId}: One batch, with its status and how many of its runs finished.
- GET /api/v1/batches/{batchId}/results: Each run's result in a batch.
- GET /api/v1/schedules (page, perPage): The project's schedules, with each one's task, cron and next run.
- GET /api/v1/schedules/{schedule_id}: One schedule, with its cron, timezone, whether it is active and its next runs.
- GET /api/v1/waitpoints/tokens (page[size]): Waitpoint tokens, with their status, such as runs waiting on a person or an outside event.
- GET /api/v1/waitpoints/tokens/{waitpointId}: One waitpoint token, with its status and when it times out.
- GET /api/v1/bulk-actions (page): Bulk actions taken on runs, such as mass cancels or replays, newest first.
- GET /api/v1/bulk-actions/{bulkActionId}: One bulk action, with who started it, its status and how many runs it touched.
- GET /api/v1/projects/{projectRef}/envvars/{env}: An environment's variables, by name, never their values.
- GET /api/v1/query/dashboards: The built-in dashboards and the queries behind them.
- GET /api/v1/query/schema: The tables and columns the query API can read.
