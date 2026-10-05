---
name: render_deploy_failures
when: A deploy on Render failed, hangs, or never went live, such as build_failed, pre_deploy_failed or update_failed, or a deploy that timed out waiting for a port or a health check
tools: [recent_deploys, list_events, search_logs, resource_status]
references: [debug/error-patterns.md, debug/log-analysis.md, debug/troubleshooting.md]
---
A failed deploy leaves the previous one serving, so the service usually still works. The question is why the new one did not go live.

1. Call `recent_deploys` and find the failed one. Its status says which stage failed:
   - build_failed: the build command failed, or ran past Render's 120 minute build limit.
   - pre_deploy_failed: the pre-deploy command, such as a database migration, failed or ran past 30 minutes. It runs on its own instance before the new code starts.
   - update_failed: the build worked but the new instances never became healthy.
   - canceled: someone or something stopped it, often a newer deploy.
2. Call `list_events` for the window. The deploy ended event carries the reason in words: a timeout with how long and why, a failed health check, an exit code, or running out of memory while starting. An image pull failed event names the image Render could not fetch.
3. Read the logs of that stage with `search_logs`:
   - For a build, `stream` build, with `text` set to error or the tool's own failure word. Missing dependencies, a language version the code does not support and a build command that needs an environment variable that is not set are the usual causes.
   - For a start that timed out, `stream` app. Render starts a web service and waits up to 15 minutes for it to listen. A web service has to listen on 0.0.0.0 at the port in the PORT variable, 10000 unless set, and one listening on localhost or another port never becomes reachable.
   - For a health check, Render only promotes a deploy once every new instance passes at the same time, and cancels it after 15 minutes otherwise. Call `resource_status` for the health check path. The path has to answer 2xx or 3xx within 5 seconds.
4. A Docker service that builds but never starts may have no CMD or ENTRYPOINT, so nothing runs.
5. The fix is in the code or the service's settings, and the previous deploy keeps serving until it lands. Say which commit failed and why, and what to change.
