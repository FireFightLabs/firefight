---
name: digitalocean_triage
when: Starting on anything wrong with an App Platform app, a Droplet or a managed database on DigitalOcean, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, resource_metrics, search_logs, app_logs]
references: [shared/error-patterns.md, troubleshooting/logs-analysis.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name. An app shows the phase of its latest deployment, a Droplet and a database their status.
2. Call `resource_status` on it. For an app, read three things: the active deployment and whether another is in progress, whether a rollback pinned the app (then nothing new deploys until someone commits or reverts it in the control panel), and each component's health, where fewer instances ready than desired means some are failing their health checks or crashing. For a Droplet, a status of off or a locked Droplet explains a lot by itself. For a database, a status other than online (creating, resizing, migrating or forking) is the answer.
3. For an app, call `recent_deploys`. A deployment shortly before the trouble began is the first suspect, so load the digitalocean_changes skill. A deployment in the ERROR phase never went live, so the one before it is still serving.
4. Call `query_metrics` for the window: cpu and memory for an app, cpu, memory and disk for a Droplet or a MySQL database. For an app, also call `resource_metrics` with `metrics` set to restarts, since restarts mean crashes. Load digitalocean_crashes when they climb, and digitalocean_resources when cpu or memory sits near 100%.
5. Read what the app printed with `search_logs` around the moment the metrics turned. `app_logs` with `type` RUN_RESTARTED reads the logs of the instances that crashed or restarted, and `type` DEPLOY the deploy step, which neither `search_logs` stream reaches.

Firefight reads the logs of the app's active deployment, so lines from before the last deployment are not there. A Droplet always reports cpu and network, but memory and disk only once the DigitalOcean metrics agent is installed on it. Only MySQL databases have metrics in DigitalOcean's API, so for other engines read their status instead.
