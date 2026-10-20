---
name: fly_triage
when: Starting on anything wrong with an app or Managed Postgres cluster on Fly.io, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, search_logs, postgres_queries]
references: [machines/machine-states.md, errors/error-codes.md, monitoring/metrics.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact app name. It shows the app's status and how many machines it has.
2. Call `resource_status` on it. Each machine shows its state (started, stopped, suspended, failed, or a passing state such as replacing), its region, its size, the image it runs, its restart policy, its health checks and its latest events. A check marked critical means Fly's proxy stops sending that machine traffic. An exit event that says it ran out of memory points at the fly_crashes skill. Machines on different images mean a deploy stopped halfway.
3. Call `recent_deploys`. A release shortly before the trouble began is the first suspect, and a failed or interrupted one means the deploy did not finish, so load the fly_deploys skill.
4. Call `query_metrics` for the window: http_5xx and requests for an app that serves traffic, cpu and memory for every app. 5xx that rise with requests point at load, and 5xx on flat traffic point at the code or something it calls. Requests and responses are counted at Fly's edge, so an app reached only over the private network shows none, which does not mean zero.
5. Read what it printed with `search_logs` around the moment the metrics turned. Fly's proxy writes its own error codes into the same logs (such as PR04 or PC01), and the fly_proxy_errors skill says what each means.
6. For a Managed Postgres cluster, `resource_status` gives its status, plan and the apps attached to it, and `postgres_queries` what it is doing: kind slow for the queries that took the most time in all, and kind active for what runs now in each database, with how long each has run and what it waits on, such as a lock. A query that waits on a lock for long, or one slow query that grew, points at the app that sends it. Fly keeps no logs or metrics of a cluster that its API reads, so those are on the cluster's Metrics tab in Fly.io.

Fly keeps logs for about 7 days and metrics for about 15, so an older incident can only be read from what was kept elsewhere.
