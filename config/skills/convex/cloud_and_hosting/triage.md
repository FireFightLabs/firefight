---
name: convex_triage
when: Starting on anything wrong with a Convex backend, before knowing what kind of problem it is
tools: [resource_status, search_errors, recent_deploys, search_logs]
references: [insights/SKILL.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `resource_status` for the deployment. A deployment that was paused, or stopped because it went over a usage limit, fails every function call, so a recent pause or stop is the answer on its own. Say who did it and when, from the audit log line.
2. Call `search_errors` for the window. A function failing far more often than the rest is where to look, so load the convex_errors skill. Errors about reading too much, running too long or write conflicts belong to the convex_limits skill.
3. Call `recent_deploys`. A push shortly before the trouble began is the first suspect, so load the convex_changes skill.
4. Read what the functions printed with `search_logs` around the moment it started, with `text` set to the function or the message the person saw.

Convex has no metrics in Firefight, so how much traffic there was is read from how many executions the logs hold. A deployment keeps only its recent function logs. When the answer says the range reaches past them, older lines are only in a log stream the team set up.
