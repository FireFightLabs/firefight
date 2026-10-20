---
name: railway_cron_jobs
when: A Railway cron job did not run, failed, was skipped, ran too long or ran late, or someone asks when it last ran
tools: [run_history, cron_runs, resource_status, search_logs, recent_deploys, list_resources]
references: [cron-jobs.md, cli/cron.md]
---
A cron job on Railway is a service with a cron schedule. Each run starts its deployment, runs until the process exits, and is listed with how it ended.

1. Call `resource_status` for the schedule and when the next run is due. The schedule is in UTC.
2. Call `run_history` on the cron job, or `cron_runs` with it as `resource`. Each run says how it ended:
   - exited is a run that finished, which reads as succeeded.
   - crashed is a run that exited with an error.
   - skipped is a run Railway did not start because the run before it was still running, so a run that never ends blocks every one after it.
   - stopped or removed is a run cut short, such as by a new deployment.
3. Read one run's lines with `run_history` and the run's id as `run`, which gives the log to read over the time it ran, or with `search_logs` over that time.
4. A run that takes longer than the time between runs makes the next ones skip. Say how long recent runs took against the schedule.
5. When no run appears at a time one was due, say so with the schedule and the latest run, and check with `recent_deploys` whether a deployment of the cron job changed around then.
