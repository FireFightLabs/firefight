---
name: vercel_ci
when: A Vercel CI run failed, is stuck or took longer than usual, or a question about a repository's checks that run on Vercel CI
tools: [ci_runs, ci_job_log]
---
Vercel CI runs a repository's jobs on Vercel for each push, apart from the project's own build.

1. Call `ci_runs` with `repository` as owner/name, and `branch` when the question is about one. Each run has its branch and commit, its status, when it started and finished and how long finished ones usually take. A run still going is running, and one that never got its jobs started failed while setting up, with the reason on its line.
2. Call `ci_runs` with `run` set to the run's id for its jobs. Each job has its outcome and, when it failed, the reason Vercel gave. The first job that failed is usually the cause, and the jobs after it may only have been skipped.
3. Call `ci_job_log` with the run's id and the job's name for its log, and use `text` to look for a word such as error or FAIL. Read up from the last lines, since the cause is usually a few lines above the final error.
4. Compare with the last run on the same branch that passed. A run of an unchanged commit that now fails points at a dependency, a secret or a flaky test, not the code.
5. Say which job failed, the line that shows why, and the commit that brought it in.
