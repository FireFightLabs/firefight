---
name: digitalocean_changes
when: Finding what changed on an App Platform app before something broke, or rolling an app back to an earlier deployment
tools: [recent_deploys, resource_status, query_metrics, app_logs, app_events, rollback, commit_rollback, revert_rollback, cancel_deployment, redeploy_app]
references: [shared/error-patterns.md, troubleshooting/logs-analysis.md]
---
1. Call `recent_deploys` for the app. Each deployment shows when it was made, its phase, what caused it (a push to the repository, a manual deploy, a change to the app's settings) and the commit each component was built from. `app_events` shows the same deployments beside each time autoscaling changed how many instances a component runs, and what moved it.
2. Call `query_metrics` for the errors or resources that went wrong, and line the moment they turned up against those times. A deployment that went out after the trouble began did not cause it.
3. A deployment in the ERROR or CANCELED phase never went live, so the deployment before it is still serving. Read why with `app_logs` and that deployment's id as `deployment`, `type` BUILD for a failed build or DEPLOY for a failed rollout, since without it `app_logs` reads the live deployment. A deployment still building is read the same way, with what it has logged so far. It can explain a fix that is not live, rarely an outage.
4. Call `resource_status` for the active deployment now. To see what the suspect deployment changed in code, compare its commit with the one before it in the repository.
5. Say which change came right before the trouble, what it was, and how sure the timing makes you.
6. To stop a bad deployment that is still building or deploying, propose `cancel_deployment` with its id. The deployment live before it keeps serving.
7. To undo a deployment that went live, propose `rollback` with `to` set to the id of the last deployment that was healthy. DigitalOcean checks first that it can go back to it, and refuses with why when it cannot. It then pins the app to that deployment, so no new deployment goes out, not even on a push, until the rollback is kept with `commit_rollback` or undone with `revert_rollback`. Say this to the person, since a fix pushed afterwards will not deploy until then. The person confirms the rollback first.
8. Once the fix is understood, propose `commit_rollback` to keep the rollback for good, or `revert_rollback` to go back to how the app was before it. Either lets the app deploy again.
9. When the code on the branch is right but the live build is not, such as a cached build that went bad, propose `redeploy_app` with `force_build` true to build the newest commit again from source. It is refused while a rollback pins the app.
