---
name: upstash_workflow
when: Finding why an Upstash Workflow run failed, is stuck, or keeps retrying a step, how long a workflow's runs usually take, or bringing failed runs back from the dead letter queue
tools: [run_history, logs_list, dlq_list, dlq_manage, workflow_manage_run]
references: [workflow/troubleshooting.md, workflow/rest-api.md, qstash/dlq.md]
---
A workflow is on the resource map by its address, part of its region's QStash, once one of its runs is among the region's latest.

1. Call `run_history` for the workflow for its runs, newest first, with each run's state, how long it took and how long finished runs usually take. A failed run names the status its last step answered and its place in the dead letter queue.
2. Call `run_history` with `run` set to a run's id for its steps, each with how it stands. The first failed step, or the last one that started and never finished, is where it stopped.
3. For a workflow not on the map yet, call `logs_list` with the region and service workflow. For a run still going, `workflow_manage_run` reads its live steps. Only read, since the same tool cancels a run.
4. Call `dlq_list` with the region and service workflow for runs whose retries ran out.
5. Match what Upstash's troubleshooting guide lists: a step inside a try and catch block, a request payload that is undefined, a signature that does not verify, an early return before the first step, or a run stuck on its first step because the destination is not reachable from QStash.
6. Once the cause is fixed, such as the destination answering again or a deploy with the fix live, propose bringing the failed runs back with `dlq_manage`, with the region, service workflow and each run's dead letter id from `dlq_list` or `run_history`. Resume continues a run from the step that failed and keeps the steps that already ran, and restart runs it from its first step, so resume fits unless a step that already ran must run again. Say which runs, how many, and which of the two, since each runs the workflow's steps again against live systems. Never bring a run back while its cause is still there, since it fails again and returns to the dead letter queue.
7. Call `run_history` for the workflow afterward to see the runs brought back finish.
8. Say which workflow and step failed, since when and why, and which runs were resumed or restarted.
