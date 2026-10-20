---
name: digitalocean_triage
when: Starting on anything wrong with an App Platform app, a Droplet or a managed database on DigitalOcean, before knowing what kind of problem it is
tools: [list_resources, resource_status, recent_deploys, query_metrics, resource_metrics, search_logs, app_logs, run_history, cancel_job_run]
references: [shared/error-patterns.md, troubleshooting/logs-analysis.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources` for the exact name. An app shows the phase of its latest deployment, a Droplet and a database their status.
2. Call `resource_status` on it. For an app, read three things: the active deployment and whether another is in progress, whether a rollback pinned the app (then nothing new deploys until the rollback is kept or undone, see the digitalocean_changes skill), and each component's health, where fewer instances ready than desired means some are failing their health checks or crashing. For a Droplet, a status of off or a locked Droplet explains a lot by itself. For a database, a status other than online (creating, resizing, migrating or forking) is the answer. An app's status also lists the alerts set up on it, and a Droplet's its latest actions, such as a reboot, resize or power cycle someone ran.
3. For an app, call `recent_deploys`. A deployment shortly before the trouble began is the first suspect, so load the digitalocean_changes skill. A deployment in the ERROR phase never went live, so the one before it is still serving.
4. Call `query_metrics` for the window: cpu and memory for an app, cpu, memory and disk for a Droplet or a MySQL database. For an app, also call `resource_metrics` with `metrics` set to restarts, since restarts mean crashes. Load digitalocean_crashes when they climb, and digitalocean_resources when cpu or memory sits near 100%.
5. Read what the app printed with `search_logs` around the moment the metrics turned. `app_logs` with `type` RUN_RESTARTED reads the logs of the instances that crashed or restarted, and `type` DEPLOY the deploy step, which neither `search_logs` stream reaches.

An app's jobs, such as a migration or a scheduled task, run as job runs. `run_history` lists them beside the deployments, and `app_logs` with `job_invocation` reads one run's lines. A job run that hangs can be stopped with `cancel_job_run`, which the person confirms first.

Firefight reads the logs of the app's active deployment, so lines from before the last deployment are not there. A Droplet always reports cpu and network, but memory and disk only once the DigitalOcean metrics agent is installed on it. Only MySQL databases have metrics in DigitalOcean's API, so for other engines read their status instead.
