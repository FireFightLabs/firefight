---
name: digitalocean_crashes
when: An App Platform app or one of its components keeps restarting, crashes, fails its health checks or has fewer instances ready than it should
tools: [resource_status, resource_metrics, app_logs, recent_deploys, restart_app]
references: [troubleshooting/logs-analysis.md, shared/error-patterns.md, troubleshooting/debug-container.md]
---
1. Call `resource_status`. Each component shows how many instances are ready of how many are desired, its health state, and its health check. Note which component is short.
2. Call `resource_metrics` with `metrics` set to restarts and memory for the window. Restarts that rise as memory reaches the top of the instance mean the process runs out of memory and is killed. Restarts on flat memory mean the process exits or fails its health check.
3. Call `app_logs` with `type` RUN_RESTARTED and the `component` from step 1. These are the last lines of the instances that crashed or were restarted, so the exception, the exit code or the out of memory kill is usually here.
4. If nothing crashed but instances are not ready, read `app_logs` with `type` RUN for health check failures, and compare the health check's path and port in the status with what the app listens on.
5. Call `recent_deploys`. Crashes that began with a deployment come from what it changed, so load digitalocean_changes and consider a rollback rather than a restart.
6. Only when the code is fine and an instance is stuck, propose `restart_app`, for the one `component` or every one. It is a rolling restart that makes a new deployment of the same code, and the person confirms it first.
