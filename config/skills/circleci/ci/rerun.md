---
name: circleci_rerun
when: Rerunning or cancelling a CircleCI workflow, such as after a flaky failure or a fix to something the build depends on
tools: [list_runs, get_run, list_workflows, get_workflow, rerun_workflow, cancel_workflow]
---
1. Rerunning changes real CI state, so it is never done while investigating. Propose it, and run it only in a chat after the person confirms, or as a step of a fix they approve.
2. Find the workflow with `list_runs`, `get_run` and `list_workflows`, and check it with `get_workflow`: rerun only a workflow that finished, and only when what failed is not the code, such as a flaky test, a network error or a service that has since come back.
3. Call `rerun_workflow` with the workflow's id and `from_failed` set, so only the failed jobs and what follows them run again and the jobs that passed are kept. Without it every job runs again from the start.
4. `cancel_workflow` stops a workflow that is running, such as a deploy that should not go out. Say what it stops before asking the person to confirm.
5. After a rerun, call `list_runs` for the project to follow the new run, and say whether it passed.
