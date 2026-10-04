---
name: railway_deploy_failures
when: A Railway deployment failed, hangs while building or deploying, or never went live
tools: [recent_deploys, resource_status, search_logs]
references: [deployments/reference.md, deployments/healthchecks.md, deployments/troubleshooting/no-start-command-could-be-found.md, deployments/troubleshooting/slow-deployments.md]
---
A failed deployment never takes traffic. The one before it keeps serving until a new one passes, so a failed deploy alone is not an outage.

1. Call `recent_deploys` and find the first FAILED deployment, with its commit. Compare it with the last one that succeeded.
2. Read its build with `search_logs`, `stream` build. The build logs read are those of the latest deployment.
   - A build that stops with no start command found means Railway could not tell how to run the app. Its builder tries the usual start scripts for each language, and otherwise the service needs a start command.
   - A missing dependency, a wrong language version or a variable the build needs points at the commit or the service's settings.
3. A build that finished and still failed died while deploying. Call `resource_status` and read the health check.
   - With a health check path, Railway asks that path on the PORT variable until it answers 2xx, for up to 300 seconds unless the service sets another timeout, then fails the deployment. The requests come from healthcheck.railway.app, so an app that only allows its own hostnames answers them with an error.
   - The check runs only while deploying, never afterwards.
4. Read what the app printed while starting with `search_logs`, `stream` app, over the minutes of the deployment.
5. Say which step failed, the line that shows it, and the commit, and whether the previous deployment is still serving. When it is not, load railway_fixes for a rollback.
