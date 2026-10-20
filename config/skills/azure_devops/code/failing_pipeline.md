---
name: azure_devops_failing_pipeline
when: Finding why an Azure Pipelines run or job fails, such as a broken build, failing tests, a job no agent picked up, or a deployment job that stopped
tools: [ci_status, pipelines, pipeline_jobs, job_log, ci_runs, search_logs, pending_approvals]
references: [pipelines/troubleshooting.md, pipelines/review-logs.md, pipelines/troubleshoot-start.md]
---
1. Call `ci_status` with the repository as `repo` or the pipeline as `pipeline`, and a `ref` when the failure is not on the default branch. It names the latest run, its failed jobs with the errors Azure DevOps recorded, and when the branch last passed.
2. A failure that began with one commit after a run of passing runs points at that commit. One that comes and goes on the same commit points at something outside the code, such as a flaky test, a service the tests reach, or the agent.
3. Read the errors the job reported before its log. A job that never started, or waited for an agent until it timed out, is not the code. Read troubleshoot-start.md for why a run does not start, such as no agent, a parallel job limit or a check waiting.
4. Call `job_log` with the run's `build_id` and its `project` for the failed step's log, read from its end, where a step says why it stopped. Pass `log_id` for a job `pipeline_jobs` listed, `text` or `regex` to find an error, and `exclude` to drop noise. Without a `build_id` it reads the newest failed run of the repository or pipeline. `search_logs` asks the same of one on the map.
5. A run waiting rather than failing may be held by an approval or a check. `ci_status` lists approvals waiting, and `pending_approvals` lists them all for a project.
6. Never rerun while investigating. When what failed is not the code, such as a flaky test, an agent that went away or a service that has since come back, propose rerunning the failed jobs and say why. When it is the code, propose a fix instead. Load azure_devops_rerun once the person wants it, since a rerun asks them first.
7. Say which job fails, the line in its log that says why, the commit it ran on, and when the branch last passed, with the run's link.
