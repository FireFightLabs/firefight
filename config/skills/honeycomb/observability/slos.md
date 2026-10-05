---
name: honeycomb_slos
when: Finding which Honeycomb SLO is burning or which trigger fired, and what that means for users
tools: [get_slos, get_triggers, run_query, search_errors]
references: [slos/SKILL.md, slos/alerting-strategy.md, slos/slo-design-guide.md]
---
1. Call `get_slos` for the environment to list the SLOs with their budget, then with the SLO's id for its detail, including how fast the budget is burning.
2. An SLO is measured by a query on the service's spans. Rerun what it counts with `run_query` over the last hours to see when the bad events began and which endpoints they come from.
3. Call `get_triggers` for the environment to see which triggers fired, what each one measures and who it notified.
4. Call `search_errors` for the service behind the SLO to see which operations fail.
5. Say which SLO is burning, how much budget is left, since when, and which requests cause it.
