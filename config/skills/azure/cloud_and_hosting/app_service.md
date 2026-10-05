---
name: azure_app_service
when: An App Service or Function app answers with errors, is slow, or broke after a deployment
tools: [query_metrics, recent_deploys, search_logs, resource_status, rollback, restart]
references: [app-service/deploy-staging-slots.md, app-service/monitor-instances-health-check.md, app-service/troubleshoot-diagnostic-logs.md, functions/functions-monitoring.md]
---
1. Call `query_metrics` with `metrics` requests, http_5xx and memory over a range that starts well before the problem. cpu is its App Service plan's, shared with every app on the plan, so a neighbour can be the cause.
2. Call `recent_deploys` for its deployments, with when, by whom and whether each succeeded, and its deployment slots.
3. Read the failing requests with `search_logs` with stream requests, and what the app printed with the app stream. A Function app's lines carry the function's name and level.
4. When a deployment through a slot swap brought the errors, the slot it came from now holds what ran in production before. Offer `rollback` with `to` set to that slot's name. Swapping again puts the last known good app back, as Microsoft's guide on slots describes. The undo is the same swap once more. An app with no slots cannot be rolled back this way, and the fix is deploying the earlier build again.
5. For an app stuck in a bad state while its code and load are fine, offer `restart`. There is no undo.
6. Say what changed, the evidence, and whether the fix is a swap, a restart, more instances on the plan, or a code change.
