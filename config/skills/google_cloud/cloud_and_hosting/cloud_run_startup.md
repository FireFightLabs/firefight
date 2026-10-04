---
name: google_cloud_cloud_run_startup
when: A Cloud Run revision fails to deploy or its instances fail to start, such as "Container failed to start" or a failed startup probe
tools: [recent_deploys, resource_status, search_logs, rollback]
references: [run/troubleshooting.md, run/container-contract.md, run/health-checks.md, run/managing-revisions.md]
---
1. Call `recent_deploys`. A newest revision whose ready state is failed, with the traffic still on an older one, means the deploy failed and the old revision is still serving. Say that first, since users may not be affected.
2. Call `resource_status` for the ready condition's message, which carries Google's reason.
3. Read the app logs of the failed revision with `search_logs` around the time it was made. The causes Google lists:
   - "Container failed to start. Failed to start and then listen on the port defined by the PORT environment variable": the app is not listening on the port Cloud Run gives it in PORT, or listens on 127.0.0.1 instead of 0.0.0.0, or crashed before it began listening. The lines just before say which.
   - A startup probe that failed: the app took longer to become ready than the probe allows.
   - An image that could not be pulled, or a missing permission to read it: the image name or the service agent's access is wrong.
   - Default credentials not found, or a secret or setting it reads at start that is missing.
4. If users are affected because the failed revision took the traffic, offer `rollback` with `to` set to the last revision that was ready.
5. Say which revision failed, the message, and what to change in the next deploy.
