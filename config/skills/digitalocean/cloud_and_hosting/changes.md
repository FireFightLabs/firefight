---
name: digitalocean_changes
when: Finding what changed on an App Platform app before something broke, or rolling an app back to an earlier deployment
tools: [recent_deploys, resource_status, query_metrics, app_logs, rollback]
references: [shared/error-patterns.md, troubleshooting/logs-analysis.md]
---
1. Call `recent_deploys` for the app. Each deployment shows when it was made, its phase, what caused it (a push to the repository, a manual deploy, a change to the app's settings) and the commit each component was built from.
2. Call `query_metrics` for the errors or resources that went wrong, and line the moment they turned up against those times. A deployment that went out after the trouble began did not cause it.
3. A deployment in the ERROR or CANCELED phase never went live, so the deployment before it is still serving. Read why with `app_logs`, `type` BUILD for a failed build or DEPLOY for a failed rollout. It can explain a fix that is not live, rarely an outage.
4. Call `resource_status` for the active deployment now. To see what the suspect deployment changed in code, compare its commit with the one before it in the repository.
5. Say which change came right before the trouble, what it was, and how sure the timing makes you.
6. To undo it, propose `rollback` with `to` set to the id of the last deployment that was healthy. DigitalOcean pins the app to that deployment, so no new deployment goes out, not even on a push, until someone commits the rollback (keeps it) or reverts it (goes back) in the control panel. Say this to the person, since a fix pushed afterwards will not deploy until then. The person confirms the rollback first.
