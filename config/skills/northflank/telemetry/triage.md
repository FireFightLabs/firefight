---
name: northflank_triage
when: Starting on anything wrong with a service or database on Northflank, before knowing what kind of problem it is
tools: [list_resources, describe_resource, list_containers, list_deployments, query_metrics, search_logs]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name. A service shows its rollout state, a database its status.
2. Call `describe_resource` on it. For a service, the rollout status COMPLETED means the latest deployment rolled out and is serving. It does not mean the process ended. Note what it runs (repository and deployed commit, or image), its plan, its health checks and its ports, since later steps lean on them.
3. Call `list_containers`. More than one container started in the window, or any failed, means restarts or a crash, so load the northflank_crashes skill. Containers stopped at the moment a new one started are a normal deploy.
4. Call `list_deployments`. A deployment shortly before the trouble began is the first suspect, so load the northflank_changes skill.
5. Call `query_metrics` for the window: http5xxResponses and requests for a service that serves traffic, cpu and memory for everything. Errors that rise with requests point at load, and errors on flat traffic point at the code or something it calls. When requests and 5xx have no data, that does not show zero, and Northflank may not record HTTP metrics here, so ask for networkIngress and read the runtime logs instead.
6. Read what it printed with `search_logs` around the moment the metrics turned.

Northflank keeps logs of stopped containers for 30 days and records metrics every 15 seconds, so a short spike shows only in a narrow range.
