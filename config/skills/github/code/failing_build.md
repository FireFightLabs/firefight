---
name: github_failing_build
when: Finding why a GitHub Actions workflow fails, such as a broken build, failing tests, or a deploy job that stopped
tools: [ci_status, workflow_runs, workflow_jobs, job_log, search_logs]
references: [actions/troubleshoot-workflows.md, actions/use-workflow-run-logs.md, actions/enable-debug-logging.md, actions/re-run-workflows-and-jobs.md]
---
1. Call `ci_status` with the repository as `repo`, and a `branch` when the failure is not on the default branch. It names the failing workflows first, the jobs and steps that failed in each, and what each environment last received. If no workflow has run, the repository's CI runs elsewhere, so ask the connection that builds it.
2. Call `workflow_runs` with `status` failure, and `branch` or `event` when they narrow it, to see when the failures began. A failure that began with one commit after passing runs points at that commit. One that comes and goes on the same commit points at something outside the code, such as a flaky test, a service the tests reach, or the runner.
3. Call `job_log` with the repository for the newest failed job's log, read from its end, where a step says why it stopped. Pass `job_id` for a job `workflow_jobs` listed, `text` or `regex` to find an error, and `exclude` to drop noise. Lines GitHub marks ##[error] are the ones a step raised. `search_logs` asks the same of a repository on the map.
4. A job that was skipped or ran when it should not have is decided by its if condition, not its code. A run that would not cancel often has a step guarded by always(). Say so rather than reading the code.
5. When the log is too thin, say that setting ACTIONS_STEP_DEBUG to true in the repository's secrets or variables makes the next run log more. That is a change a person makes.
6. Never rerun while investigating. When what failed is not the code, such as a flaky test, a timeout or a service that has since come back, propose rerunning only the failed jobs, or the whole run, and say why. When it is the code, propose a fix instead. Load github_rerun once the person wants it, since a rerun asks them first.
7. Say which job and step fail, the line in its log that says why, the commit it ran on, and when the workflow last passed, with the job's link.
