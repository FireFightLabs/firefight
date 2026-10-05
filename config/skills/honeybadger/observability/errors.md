---
name: honeybadger_errors
when: Finding why one Honeybadger error happens, who it reaches, and which deploy brought it
tools: [list_faults, get_fault, list_fault_notices, list_fault_affected_users, query_insights, get_project_report]
---
1. Find the fault with `list_faults` for the project, ordered by recent or frequent, with a search for its class or message. occurred_after and occurred_before take an RFC 3339 time, and one written another way is ignored without a word, so write them in full, such as 2026-10-04T09:00:00Z.
2. Call `get_fault` for its class, message, component and action, how many times it happened and whether it is resolved.
3. Call `list_fault_notices` for its latest occurrences. Each notice carries the request, its params and context, the backtrace and the revision that was deployed, so the first notice after a deploy names the deploy.
4. Call `list_fault_affected_users` to say how many people it reaches.
5. Call `get_project_report` with notices_per_day, or `query_insights` with a BadgerQL query over its ts range (PT3H by default), to see whether it is new or has been happening for days.
6. Say what fails, where in the code, since when, for how many people, and with which deploy. Resolving or assigning a fault is for a person to ask for.
