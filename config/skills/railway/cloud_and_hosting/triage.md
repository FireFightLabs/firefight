---
name: railway_triage
when: Starting on anything wrong with a service, database or cron job on Railway, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, search_logs, api_read]
references: [api/index.md, deployments/reference.md, observability/logs.md, observability/metrics.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name. Each service shows the status of its latest deployment, and a database is a service that runs a database image. It also lists the project's other environments, PR environments with their pull request, and passing one as `environment` lists that environment's services. The shared reads, such as `resource_status`, `recent_deploys`, `query_metrics` and `search_logs`, read only the connection's own environment, so another environment is read with `api_read` and its id.
2. Call `resource_status` on it. Read the latest deployment's status and the state of each replica, then what it runs, its start command, its health check, its restart policy and whether it sleeps when idle, since later steps lean on them.
3. Read the status and load the skill that fits:
   - FAILED means the build or the deploy never went live, and the deployment before it keeps serving. Load railway_deploy_failures.
   - CRASHED, or replicas that crashed or keep restarting, means the process exits after it started. Load railway_crashes.
   - SLEEPING means the service sleeps when idle and wakes on the next request, so a slow first request is expected.
   - SUCCESS with visitors seeing errors, or a 502 that says the application failed to respond, means the proxy cannot reach it. Load railway_failed_to_respond.
   - A cron job that failed, was skipped or did not run. Load railway_cron_jobs.
4. Call `recent_deploys`. A deployment shortly before the trouble began is the first suspect. Railway also redeploys on its own when it moves a service to another host, so a deployment nobody started is not always a code change.
5. Call `query_metrics` for the window: cpu and memory for everything, and requests and http_5xx for a service with a public domain. Request counts come from Railway's edge, so a service reached only over the private network has none, which does not show zero.
6. Read what it printed with `search_logs` around the moment the metrics turned. Railway stores each line with a level, so errors read as error.

Railway keeps logs for 7 days on Hobby and 30 on Pro, and metrics for up to 30 days.
