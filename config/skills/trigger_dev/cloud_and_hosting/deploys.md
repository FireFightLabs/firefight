---
name: trigger_dev_deploys
when: Finding whether a Trigger.dev deploy broke a task, and rolling the environment back to an earlier version
tools: [recent_deploys, list_runs, search_errors, rollback]
references: [deployment.md, runs.md]
---
1. Call `recent_deploys`. Each deployment shows its version, status, when it deployed, its git details and, for one that failed, why. A version is the whole environment, every task in it at once.
2. Call `list_runs` for the task over a window around the deploy. Each run names its version. Failures that start with the new version, while runs on the one before succeeded, point at the deploy.
3. Call `search_errors` for the task. An error group first seen right after the deploy points the same way. A deploy that came after the trouble began did not cause it.
4. A deployment that failed to build or deploy did not change what runs. The previous version keeps running, so it explains a fix that is not live, rarely an outage.
5. To roll back, call `rollback` with `to` set to the version before the bad one, one that deployed. It makes that version current for every task in the environment, not only this one. New runs start on it. Runs already started, and their retries, keep the version they started on. Say this to the person before asking for the change, and that the next deploy replaces it again unless the code is fixed.
6. Say which version came right before the trouble, what it changed if its git details say, and how sure the timing makes you.
