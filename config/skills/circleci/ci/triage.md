---
name: circleci_triage
when: Any question about builds or tests CircleCI runs, such as whether a branch is failing, why a run failed, or what to rerun
tools: [list_runs, get_run, list_workflows, get_workflow, list_jobs, get_job]
---
How CircleCI is reached: its tools chain from a project down to one job. `list_runs` lists a project's runs, by the project's slug such as gh/acme/web or bb/acme/web, or your own runs across every project, and filters by branch or status. Each run's id feeds `get_run`, a run's id feeds `list_workflows`, a workflow's id feeds `list_jobs`, and a job's id feeds `get_job`. `resource_status` with connection circleci asks `list_runs` for a GitHub or Bitbucket repository on the resource map. A project connected through CircleCI's GitHub App or GitLab is named circleci/<organization id>/<project id>, which only CircleCI's project settings show, so ask the person for it when a slug like gh/acme/web finds nothing.

1. Call `list_runs` for the project on the branch that matters, usually the default branch, to see the latest runs and their outcome. A run that failed after a string of passing ones is new, and one failing for days is older than the incident.
2. Call `get_run` for the failed run. Its outcome, the commit and branch it built, and any config errors are there. A run with config errors never started its workflows, so the problem is the config, not the code.
3. Call `list_workflows` for the run and `list_jobs` for the workflow that failed, then `get_job` for the failed job, whose steps show which one exited non zero.
4. Then load the skill that fits: circleci_failing_build for why a job failed, circleci_flaky_tests when a test fails only sometimes, circleci_breaking_change to find the change that started it, circleci_rerun when rerunning is the fix.
5. Say which run, workflow and job failed, at which step, and what the evidence shows. While investigating you only read, so a rerun or a cancel is something you propose for a person to confirm.
