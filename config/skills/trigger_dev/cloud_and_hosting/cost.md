---
name: trigger_dev_cost
when: Watching or explaining what an environment's Trigger.dev runs cost, or which task costs more than before
tools: [run_costs, list_runs, list_tasks]
signals: [cost]
---
1. Read the cost of the runs by day with `run_costs` and `by` day, then by month with `by` month and `months` 3.
2. Trigger.dev reports cost per run, so a busy environment is read for its newest runs only, and the answer says when it was cut. Say how far back the figures go.
3. Find the task that grew and since when, then read its runs with `list_runs` for whether it runs more often, longer or on a larger machine.
