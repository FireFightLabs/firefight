---
name: circleci_rerun
when: Rerunning or cancelling a CircleCI workflow, such as after a flaky failure or a fix to something the build depends on, or running a project's pipeline on a branch or tag
tools: [ci_status, ci_runs, list_runs, get_run, list_workflows, get_workflow, rerun_workflow, cancel_workflow, run_pipeline]
---
1. Each of these changes real CI, so none is done while investigating. Propose it, say what it does and why, and call it only in a chat once the person agrees, or as a step of a fix they approve. It runs as them, and an approval rule can hold it.
2. Find the workflow with `ci_status`, `list_runs`, `get_run` and `list_workflows`, and check it with `get_workflow`: rerun only a workflow that ended, and only when what failed is not the code, such as a flaky test, a network error or a service that has since come back.
3. Call `rerun_workflow` with the workflow's id and `from_failed` set, so only the failed jobs and what follows them run again and the jobs that passed are kept. Without it every job runs again from the start.
4. `cancel_workflow` stops a workflow that has not ended, such as a deploy that should not go out. Say what it stops before asking the person to confirm.
5. `run_pipeline` runs a project's pipeline on a branch or tag, the default branch when none is named, with `parameters` by name when the person gives them. Name `pipeline` when the project has more than one. Never put a secret in `parameters`, since what Halon passes is shown and kept. A pipeline that deploys ships whatever is on that branch, so say which before the person agrees.
6. When CircleCI refuses, the answer says why, usually that the token's user may not run or manage the project's pipelines. Tell the person, and do not try again until it is in place.
7. Each answer names the new run or workflow and links it. Follow it with `ci_runs` and its run's id, or `get_workflow`, and say whether it passed.
