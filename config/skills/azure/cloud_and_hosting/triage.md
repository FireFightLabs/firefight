---
name: azure_triage
when: Starting on anything wrong with an App Service or Function app, Container App, Azure SQL database or PostgreSQL flexible server on Azure, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, search_logs]
references: [app-service/overview-diagnostics.md, app-service/troubleshoot-diagnostic-logs.md, container-apps/log-options.md, monitor/diagnostic-settings.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name, kind and resource group. An app shows whether it is running or stopped, a database its status.
2. Call `resource_status` on it. For an App Service app, note its plan and how many instances the plan runs, since every app on the plan shares them. For a Container App, note its revision mode, which revisions take the traffic, and its fewest and most replicas.
3. Call `recent_deploys` for an app. A deployment or revision shortly before the trouble began is the first suspect. Load azure_app_service for an App Service or Function app, azure_container_apps for a Container App.
4. Call `query_metrics` for the window: requests and http_5xx for an app, cpu and memory for everything. Errors that rise with requests point at load, and errors on flat traffic point at the code or something it calls.
5. Read what it printed with `search_logs` around the moment the metrics turned. Azure keeps these in Log Analytics only where a diagnostic setting sends them there, or for a Container App where its environment sends its logs. When there are none, say so and lean on the metrics.

For a database, load azure_sql or azure_postgresql. Log Analytics takes a few minutes to receive new lines, so the last minutes may be missing.
