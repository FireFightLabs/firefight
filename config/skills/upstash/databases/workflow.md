---
name: upstash_workflow
when: Finding why an Upstash Workflow run failed, is stuck, or keeps retrying a step
tools: [logs_list, dlq_list, workflow_manage_run]
references: [workflow/troubleshooting.md, workflow/rest-api.md, qstash/dlq.md]
---
1. Call `logs_list` with the region and service workflow over the trouble for the runs, newest first, with each run's state and the step it reached.
2. For a failed or stuck run, call `workflow_manage_run` to read its steps. Only read, since the same tool cancels a run. The last step that started and never finished is where it stopped, and the destination's answer to it says why.
3. Call `dlq_list` with the region and service workflow for runs whose retries ran out.
4. Match what Upstash's troubleshooting guide lists: a step inside a try and catch block, a request payload that is undefined, a signature that does not verify, an early return before the first step, or a run stuck on its first step because the destination is not reachable from QStash.
5. Say which workflow and step fail, since when and why. Restarting or resuming a run from the dead letter queue is for a person to decide.
