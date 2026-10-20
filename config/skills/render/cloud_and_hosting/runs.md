---
name: render_runs
when: A cron job, one-off job or workflow task on Render failed, ran long, did not run or needs following, such as a nightly cron job that stopped succeeding, a migration run as a one-off job, or a workflow's task runs and their retries
tools: [run_history, cron_runs, job_runs, task_runs, search_logs, resource_status, list_events]
references: [debug/error-patterns.md, debug/log-analysis.md]
---
Render keeps three kinds of runs apart from deploys, and each is run history.

1. A cron job's scheduled runs: `run_history` on the cron job, or `cron_runs`, lists the runs of the last 30 days with how each ended and why a failed one failed, such as ran out of memory or exited with a code. A run that started by hand says who started it. `resource_status` gives its schedule and when it last succeeded. Its deploys are a separate history, `run_history` with `name` deploy.
2. A service's one-off jobs, a command run once on a copy of the service such as a migration: `run_history` with `name` job, or `job_runs`, lists them with their command. Name a job by its id to read why it ended, and its part points at that job's own lines.
3. A workflow's task runs: `run_history` on the workflow, or `task_runs`, names each run by its task, with its error and how many times it was retried. Name a run by its id to read each attempt and each task run it started, each pointing at its own lines. A workflow's runs send no live updates, so a watch on one reads it each minute.
4. A run that failed points at its own log first. Read it before anything else, then `list_events` on a cron job or service for instances that failed around the same time.
5. Starting, triggering or cancelling a cron job's run, and starting or cancelling a one-off job or a task run, are steps for a person in Render's dashboard or CLI. Say which.
