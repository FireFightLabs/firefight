---
name: northflank_jobs
when: Finding why a cron or manual job on Northflank failed, did not run, ran too long or ran short of memory, or following a job run to its end
tools: [list_jobs, job_runs, resource_status, search_logs, query_metrics, recent_builds, build_logs, run_history]
---
1. Call `list_jobs` for the exact name, whether it runs on a schedule or by hand, and whether it is suspended. A suspended cron job does not run at all.
2. Call `resource_status` for the job: its schedule and what happens when a run is still going at the next one, its retries, its time limit and plan, and its latest runs.
3. Call `job_runs` for it. Look at when runs started, how they ended, and how many attempts failed. Gaps between scheduled runs mean runs did not start. Each run has an id, and `run` reads one run alone, however old.
4. Read why a run failed with `search_logs`, the job as `resource` and the run's id as `run`, with a `regex` for error|exception|fatal. The last lines it printed usually say why.
5. A run that ends without saying why may have run out of memory. Call `query_metrics` for the job with `metrics` memory and cpu over the run's time.
6. A job that builds its own code can fail before it runs. `recent_builds` lists its builds, and `build_logs` with a failed one's id as `build` says where the build stopped.
7. A run that failed after several attempts used its retries. A run that kept going until it was stopped hit its time limit. Both limits are set on the job and can be raised in Northflank when the work legitimately needs more.
8. To be told when a run ends, start a watch with `run_history` on the job, which follows its newest run, or the one named by `run`.
9. Say which runs failed, since when, whether they fail every time or only sometimes, and what the logs say.

The token needs permission to read jobs and view their observability. When Northflank refuses, say that the token's role needs Project, Jobs, General, Read, and Project, Jobs, Deployment, View Observability for the logs and metrics.
