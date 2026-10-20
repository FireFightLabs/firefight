---
name: circleci_triage
when: Any question about builds or tests CircleCI runs, such as whether a branch is failing, why a run failed, or what to rerun
tools: [list_projects, ci_status, ci_runs, list_runs, get_run, list_workflows, get_workflow, list_jobs, get_job]
---
How CircleCI is reached: its tools chain from a project down to one job. A project is named by its slug, such as gh/acme/web, its name, its id, or the address of the repository it builds, and `list_projects` lists them. Each CircleCI project is on the resource map as a pipeline built from its repository, so `resource_status`, `run_history`, `search_logs` with stream build, `recent_deploys` and `rollback` answer for it by name. `list_runs` lists a project's runs and filters by branch or how they stand. A run's id feeds `get_run` and `list_workflows`, a workflow's id feeds `list_jobs`, and a job's id feeds `get_job`.

A connection made through CircleCI's hosted MCP server has only that server's tools: `list_runs` there takes the project's slug, such as gh/acme/web, and a project connected through CircleCI's GitHub App or GitLab is named circleci/<organization id>/<project id>, which only CircleCI's project settings show, so ask the person for it when a slug like gh/acme/web finds nothing. A connection made with a personal API token finds any project from its repository's address.

1. Call `ci_status` for the project, or `resource_status` for it on the map. It gives the newest run on the default branch with its failed jobs, how the last runs went and since when it fails, and what each deploy component runs in each environment. A run that failed after a string of passing ones is new, and one failing for days is older than the incident.
2. Call `get_run` for the failed run. Its outcome, the commit and branch it built, and any config errors are there. A run with config errors never started its workflows, so the problem is the config, not the code.
3. Call `list_jobs` for the workflow that failed, then `get_job` for the failed job, whose steps show which one exited with a code other than 0. `ci_runs` with the run's id gives every job of every workflow in one call.
4. Then load the skill that fits: circleci_failing_build for why a job failed, circleci_flaky_tests when a test fails only sometimes, circleci_breaking_change to find the change that started it, circleci_rerun when rerunning is the fix, circleci_deploys for what went out and putting it back.
5. Say which run, workflow and job failed, at which step, and what the evidence shows, with the link each answer gives. While investigating you only read, so a rerun, a cancel, an approval or a rollback is something you propose for a person to confirm.
