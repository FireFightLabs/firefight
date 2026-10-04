---
name: honeycomb_triage
when: Any question about a service Honeycomb watches, such as why it fails or slows down, which SLO is burning, which trigger fired, or what changed around it
tools: [get_workspace_context, get_slos, get_triggers, search_traces, search_errors, query_metrics, run_query, find_queries, get_service_map]
references: [investigation/SKILL.md, investigation/investigation-playbooks.md, queries/query-examples.md]
---
How Honeycomb is reached: `search_traces`, `search_errors` and `query_metrics` ask Honeycomb for a service on the resource map by its service.name, in the Honeycomb environment the connection was set up for. Honeycomb's own `run_query` reaches every dataset and column, including services that are not on the map, and its answer carries a link to the same query in Honeycomb, which goes in your answer.

1. Call `get_workspace_context` when you need the environments and their datasets, since every Honeycomb query names its environment by slug.
2. Call `get_slos` for the environment to see which SLOs are burning their error budget, and `get_triggers` for the triggers that fired. They tell you how bad it is and where to look.
3. Call `query_metrics` with requests, then with errors, for the service over a range that starts well before the problem, to find the minute it began and whether it is still going.
4. Call `search_errors` for the operations whose spans failed, and `search_traces` for the slowest traces. Then load the skill that fits: honeycomb_errors for failing requests, honeycomb_latency for slow ones.
5. Call `find_queries` for queries the team ran before about the same service or symptom, which are often the fastest way in.
6. On an Enterprise team, `get_service_map` shows which services call which, with their latency, so a slow or failing dependency stands out.
