---
name: circleci_failing_build
when: Finding why a CircleCI job failed, from its failed steps, their output, its tests and its artifacts
tools: [list_runs, get_run, list_workflows, list_jobs, get_job, get_job_logs, list_job_tests, list_artifacts]
---
1. Find the failed job: `list_runs` for the project and branch, `get_run` for the failed run, `list_workflows` for its workflows and `list_jobs` for the failed workflow. Keep the job's id.
2. Call `get_job` for the job. Each step has its outcome and exit code, so the first step that failed is where to look, and an exit code of 137 or a step that ran until it was stopped points at memory or a timeout rather than the code.
3. Call `get_job_logs` for the job. Without a step named it reads the failed steps, which is usually what you want. Read from the end of the output, where the error is, and quote the lines that say what went wrong.
4. When the failed step ran tests, call `list_job_tests` for the job. It returns the failing tests with their messages, and `all` adds the ones that passed or were skipped, which shows whether a test that failed here usually passes.
5. Call `list_artifacts` when the logs point at a report the job saved, such as test results or coverage.
6. Say the job, the step, the error in its own words and what it means: a failing test, a dependency that would not install, a missing secret or a setting in the config, or the machine running out of memory or time.
