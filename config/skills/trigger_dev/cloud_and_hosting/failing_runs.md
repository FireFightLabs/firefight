---
name: trigger_dev_failing_runs
when: Runs of a Trigger.dev task are failing, crashing or timing out, and the cause is not known yet
tools: [search_errors, list_runs, run_details, search_logs, query_metrics]
references: [runs.md, errors-retrying.md, machines.md, max-duration.md, logging.md]
---
1. Call `search_errors` for the task over the window. Each group is one kind of error with how often it happened in the range. Note the id of the one that matters most.
2. Call `list_runs` with that id as `error` to see the runs behind it, and their versions. Runs failing only on the newest version point at the deploy, so load the trigger_dev_deploys skill.
3. Call `run_details` on one failed run. Read each attempt's error and stack. How the run ended says where to look:
   - Failed: the task's own code threw, and the stack names the line. A run is retried by its retry settings before it fails.
   - Crashed: the worker process died, most often because it ran out of memory. Crashed runs are not retried. An out of memory error names the machine's limit. Call `query_metrics` with memory for the task to see how close its runs come to it.
   - Timed out, or an error about maximum duration: the run exceeded its maxDuration, often because something it calls got slow.
   - System failure: an error on Trigger.dev's side rather than the task's.
4. Call `search_logs` for the task with `text` from the error message, or with `regex`, to see what the runs logged just before it.
5. Say which error, since when, on which version, what the attempts show and how sure you are. Fixing the code, raising the machine size or the maxDuration are changes in the task's code, made by a person and deployed.
