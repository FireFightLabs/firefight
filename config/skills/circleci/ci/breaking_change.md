---
name: circleci_breaking_change
when: Finding which change started a CircleCI build failure on a branch that used to pass
tools: [list_runs, get_run, list_workflows, list_jobs, get_job_logs]
---
1. Call `list_runs` for the project and branch, and find the newest run that passed and the oldest run after it that failed. The change that broke the build arrived between their commits.
2. Call `get_run` for both to read the commit each one built, with its branch and subject.
3. Read the failing run's error with `list_workflows`, `list_jobs` and `get_job_logs`, so you know what to look for in the change.
4. With the code host connected, compare the two commits with its own tools to see what changed, such as a dependency bump, a config change or the file the error names. The same failure on a branch nobody pushed to points elsewhere, such as an image, an orb or a service the build depends on.
5. Say the last passing and first failing commits, the change between them that best explains the error, and the evidence.
