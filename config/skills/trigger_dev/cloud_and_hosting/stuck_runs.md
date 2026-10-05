---
name: trigger_dev_stuck_runs
when: Runs of a Trigger.dev task are waiting and not starting, such as queued, delayed or pending version
tools: [list_runs, resource_status, list_queues, list_tasks]
references: [queues.md, concurrency.md, troubleshooting.md, limits.md]
---
1. Call `list_runs` for the task with `status` set to the waiting states (queued, pending version) to see how many wait and since when.
2. Runs in Pending version wait for a version that holds their task and queue. Call `list_tasks`. A task missing from the deployed version, renamed or removed, keeps them waiting until a version with it is deployed. A run triggered on a queue no deployed task declares waits the same way.
3. Call `resource_status` on the task, then `list_queues`. For each queue and concurrency limit it shows how many runs execute and how many wait:
   - a paused queue or limit starts nothing until someone resumes it
   - a queue whose executing runs equal its limit is full, so runs wait for a slot, often behind slow runs or runs waiting on child runs
   - runs waiting in many queues at once, none of them at its own limit, point at the environment's own concurrency limit, which caps every queue together. These tools do not show it, so ask the person to check it in Trigger.dev.
4. Few runs waiting and few executing, with nothing paused, points at Trigger.dev's side. Check its status page.
5. Say what holds the runs, since when and what would release them. Resuming a queue, raising a limit and deploying a missing task are changes a person makes in Trigger.dev or in the code.
