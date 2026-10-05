---
name: gitlab_failing_pipeline
when: Finding why a GitLab pipeline or job fails, such as a broken build, failing tests, a job that could not pull its image, or a deployment job that stopped
tools: [ci_status, pipelines, pipeline_jobs, job_log, search_logs]
references: [ci/debugging.md, ci/job-troubleshooting.md, ci/job-logs.md]
---
1. Call `ci_status` with the project as `repo`, and a `ref` when the failure is not on the default branch. It names the latest pipeline, its failed jobs with why GitLab says each failed, and when the branch last passed.
2. A failure that began with one commit after a run of passing pipelines points at that commit. One that comes and goes on the same commit points at something outside the code, such as a flaky test, a service the tests reach, or the runner.
3. Read the reason GitLab gives before the log. stuck or timeout reasons mean the job never ran to the end, such as no runner picking it up within an hour, or no update for 30 minutes, so the code is not the first suspect. A script failure means a command in the job exited with an error.
4. Call `job_log` with the project for the newest failed job's log, read from its end, where a job says why it stopped. Pass `job_id` for a job `pipeline_jobs` listed, `text` or `regex` to find an error, and `exclude` to drop noise. `search_logs` asks the same of a project on the map.
5. Some failures name their own cause in the log: Failed to pull image is an image the job's token may not reach, often another project's registry that does not allow this one. Not allowed to download code is the same for a repository.
6. When a job has no log, GitLab no longer keeps it or the job never started, so say so and read an earlier failure from `pipelines` with `status` failed.
7. Never retry while investigating. When what failed is not the code, such as a flaky test, a stuck job or a runner that went away, propose retrying the failed jobs and say why. When it is the code, propose a fix instead. Load gitlab_rerun once the person wants it, since a retry asks them first.
8. Say which job fails, the line in its log that says why, the commit it ran on, and when the branch last passed, with the job's link.
