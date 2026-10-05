---
name: trigger_dev_triage
when: Starting on anything wrong with a Trigger.dev task, before knowing what kind of problem it is
tools: [list_tasks, resource_status, search_errors, list_runs, recent_deploys, query_metrics, list_queues]
references: [runs.md, deployment.md, troubleshooting.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_tasks` for the exact identifier. It lists the tasks in the newest version deployed to the environment. A task missing from it cannot run there, and its runs wait in Pending version until a version that has it is deployed.
2. Call `resource_status` on the task. It says which version it runs in, its queue (how many runs execute, how many wait, whether the queue is paused) and how its runs in the last hour ended.
3. Call `search_errors` for the task over the window. An error group whose count jumped, or one first seen during the trouble, is the lead, so load the trigger_dev_failing_runs skill.
4. Many runs waiting while few execute, or runs sitting in Pending version, means runs are not starting rather than failing, so load the trigger_dev_stuck_runs skill.
5. Call `recent_deploys`. A version deployed shortly before the trouble began is the first suspect, so load the trigger_dev_deploys skill.
6. Call `query_metrics` for the window with requests and errors. Failed runs rising with runs started points at load or something the task calls. Failures on flat traffic point at the code or a dependency that broke.

Every run is locked to the version it started on, and so are its retries, so a fix deployed now does not change runs already going.
