---
name: runbooks
when: Attaching a runbook to an incident, or finding which runbook fits one
tools: [search_runbooks, get_runbook, attach_runbook]
---
1. Find the runbook with `search_runbooks`, using the words the person or the incident used. Read one with `get_runbook` only when you need its steps to choose between several.
2. When several fit, ask which, naming them. Runbooks whose conditions match attach on their own, so one may already be there.
3. Call `attach_runbook` with the `incident` and the `runbook` slug. Attaching twice changes nothing.
