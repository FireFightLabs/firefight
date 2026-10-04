---
name: modal_triage
when: Starting on anything wrong with an app on Modal, before knowing what kind of problem it is
tools: [list_apps, resource_status, recent_deploys, app_logs]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_apps` for the exact name. Only a deployed app keeps serving. An app that is stopped cannot be started again, only deployed anew, so a stopped app that should be live is the answer on its own.
2. Call `resource_status` on it. Note the version that is live and when it went out, how many containers run now, and its functions with their GPU, schedule and whether they serve the web. No containers running is normal for a function that scales to zero, and not a fault by itself.
3. Call `recent_deploys`. A version that went out shortly before the trouble began is the first suspect, so load the modal_deploys skill.
4. Call `app_logs` for the window with `source` system. Modal writes there what happens to containers: a crash, an out of memory kill, a timeout, a heartbeat timeout or a preemption. Any of these means loading modal_crashes or modal_timeouts.
5. Call `app_logs` again with `source` stderr and the `function` that is failing, to read the errors the code raised. Narrow with `text` once a message repeats.
6. Slow answers with no errors point at cold starts, so load modal_cold_starts.

Modal offers no metrics through its API, so the logs and the containers running are the evidence. Its dashboard, at each app's page, has the charts.
