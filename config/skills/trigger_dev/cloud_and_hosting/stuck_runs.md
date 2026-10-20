---
name: trigger_dev_stuck_runs
when: Runs of a Trigger.dev task are waiting and not starting, such as queued, delayed or pending version
tools: [list_runs, resource_status, list_queues, list_tasks, pause_queue, resume_queue, override_queue_concurrency, reset_queue_concurrency, resume_concurrency_limit, override_concurrency_limit, reset_concurrency_limit, bulk_cancel_runs, abort_bulk_action]
references: [queues.md, concurrency.md, troubleshooting.md, limits.md]
---
1. Call `list_runs` for the task with `status` set to the waiting states (queued, pending version) to see how many wait and since when.
2. Runs in Pending version wait for a version that holds their task and queue. Call `list_tasks`. A task missing from the deployed version, renamed or removed, keeps them waiting until a version with it is deployed. A run triggered on a queue no deployed task declares waits the same way.
3. Call `resource_status` on the task, then `list_queues`. For each queue and concurrency limit it shows how many runs execute and how many wait:
   - a paused queue or limit starts nothing until someone resumes it
   - a queue whose executing runs equal its limit is full, so runs wait for a slot, often behind slow runs or runs waiting on child runs
   - runs waiting in many queues at once, none of them at its own limit, point at the environment's own concurrency limit, which caps every queue together. These tools do not show it, so ask the person to check it in Trigger.dev.
4. Few runs waiting and few executing, with nothing paused, points at Trigger.dev's side. Check its status page.
5. Say what holds the runs, since when and what would release them.
6. What Halon can change, each confirmed by the person first:
   - a paused queue or limit: `resume_queue` or `resume_concurrency_limit`, once whoever paused it agrees the reason is gone
   - a full queue or limit: `override_queue_concurrency` or `override_concurrency_limit` lets more run at once, at most the environment's own limit, until `reset_queue_concurrency` or `reset_concurrency_limit` puts the code's value back. More at once also means more load on whatever the task calls, so say so
   - runs that pile up and should not run at all, such as a task flooding something downstream: `pause_queue` holds the rest while the cause is found, and `bulk_cancel_runs` with the task and the waiting states cancels them. A bulk action that picked the wrong runs is stopped with `abort_bulk_action`, which leaves the runs it already did as they are
   Deploying a missing task is a change in the code, made by a person.
