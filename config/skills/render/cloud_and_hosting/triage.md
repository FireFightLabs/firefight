---
name: render_triage
when: Starting on anything wrong with a service, static site, cron job, Postgres database or Key Value instance on Render, before knowing what kind of problem it is
tools: [list_resources, resource_status, list_events, recent_deploys, query_metrics, search_logs]
references: [debug/quick-workflows.md, debug/troubleshooting.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name. A service that is suspended says by what. Suspended by stuck_crashlooping means Render gave up on it after it kept failing to start or stay healthy for a day, so load the render_crashes skill.
2. Call `resource_status` on it. For a service it gives the plan, region, instances or autoscaling, what it runs, its health check path, its latest deploy and its events of the last day. For a datastore it gives the status, which is available when all is well, and any maintenance.
3. For a service, call `list_events` for the window. A server failed event says why an instance stopped (ran out of memory, exited with a code, failed its health check, timed out), so load the render_crashes skill. A deploy ended or build ended as failed means the latest change never went live, so load the render_deploy_failures skill.
4. Call `recent_deploys`. A deploy that went live shortly before the trouble began is the first suspect. Render keeps the previous deploy serving when a new one fails, so a failed deploy alone does not take a service down.
5. Call `query_metrics` for the window: http_5xx and requests for a web service, cpu and memory for everything, tcp_connections for a datastore. Errors that rise with requests point at load, and errors on flat traffic point at the code or something it calls. For 5xx responses, load the render_http_errors skill.
6. Read what it printed with `search_logs` around the moment the metrics turned, with `text` set to what the error says.

Render keeps logs and metrics for 7 days on Hobby workspaces, 14 on Pro and 30 on Scale and Enterprise, so an older window comes back empty rather than wrong.
