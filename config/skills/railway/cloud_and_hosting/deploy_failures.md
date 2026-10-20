---
name: railway_deploy_failures
when: A Railway deployment failed, hangs while building or deploying, waits for approval, or never went live, in the connection's environment or a PR environment
tools: [recent_deploys, resource_status, search_logs, run_history, list_resources, api_read]
references: [api/index.md, deployments/reference.md, deployments/healthchecks.md, deployments/troubleshooting/no-start-command-could-be-found.md, deployments/troubleshooting/slow-deployments.md]
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
5. Call `run_history` with the deployment's id as `run` for each step it went through, such as build, healthcheck and draining the old instances, and the error the failed one gave. A deployment removed before it went live reads as cancelled.
6. A deployment that sits queued with the status NEEDS_APPROVAL or WAITING is held until someone approves it, such as a push by a GitHub user with no linked Railway account. It is not stuck. Approving it is a fix in railway_fixes.
7. A pull request's deployment runs in its PR environment, which `list_resources` lists with the pull request it is for, and `list_resources` with `environment` lists that environment's services. The shared reads, `recent_deploys`, `search_logs` and `run_history`, read only the connection's own environment, so read a PR environment's deployments and logs with `api_read`, passing its environment id, as the railway_api skill shows.
8. Say which step failed, the line that shows it, and the commit, and whether the previous deployment is still serving. When it is not, load railway_fixes for a rollback.
