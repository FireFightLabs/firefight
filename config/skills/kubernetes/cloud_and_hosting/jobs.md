---
name: kubernetes_jobs
when: A Kubernetes cronjob did not run, ran late, ran twice, or its jobs fail, and a one off job that failed or never finished
tools: [resource_status, run_history, workload_logs, search_logs, list_events]
references: [workloads/cron-jobs.md, workloads/job.md, workloads/pod-lifecycle.md]
---
1. Call `resource_status` on the cronjob. It shows the schedule and time zone, whether it is suspended, its concurrency policy, when it last ran and last succeeded, and its recent jobs with how each ended.
2. Call `run_history` on the cronjob or job for its runs, newest first, each with how it ended, its failure reason, when it started and finished, and how long finished runs usually take. A run started by hand says so. With `run` set to a job's name it lists each pod with its phase, why its container stopped and its exit code, and how to read that pod's log.
3. Match what it shows:
   - Suspended: nothing runs until it is resumed.
   - Did not run on time: with a starting deadline set, a run that cannot start within it is skipped. A cronjob that missed more than 100 schedules since it last ran starts nothing and records an error, which happens after the controller was down for long or a clock moved.
   - Forbid concurrency skips a run while the last one is still going, and Replace stops the running one for the new.
   - A job failed with BackoffLimitExceeded: its pods failed more times than its backoff limit, which is 6 unless set. Read why with the steps below.
   - A job failed with DeadlineExceeded: it ran longer than its active deadline and its pods were stopped.
4. Read what the job's pods printed with `search_logs` on the cronjob or job, which reads the newest job's pods. Kubernetes keeps logs only while the pods exist, and a cronjob keeps only its last 3 successful and last failed job unless its history limits say otherwise.
5. The pods `resource_status` lists for a cronjob are its newest job's, each with its exit code and why it stopped. For a pod of an older job that is still kept, read it with `workload_logs` and `pod`, by the name `run_history` with that job as `run` gives it.
6. Call `list_events` with `resource` set to the cronjob's name for jobs it could not create and pods that could not be scheduled.
