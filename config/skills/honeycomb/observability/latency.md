---
name: honeycomb_latency
when: Finding why a service Honeycomb watches is slow, times out, or its latency rose
tools: [run_query, run_bubbleup, search_traces, get_trace, get_dataset_columns]
references: [investigation/SKILL.md, investigation/bubbleup-guide.md, investigation/trace-exploration.md, queries/query-examples.md, queries/result-interpretation.md]
---
1. Call `run_query` for the service's root spans (is_root is true and service.name is the service) with the P99 and HEATMAP of duration_ms, broken down by name, over a range that starts well before it slowed. Find the minute it began and whether every endpoint slowed or one.
   - Every endpoint slowing together points at something they share: a database, a dependency or load.
   - One endpoint slowing alone points at its own code or what it calls.
2. Call `run_bubbleup` on that query's result, selecting the slow requests. It compares them with the rest across every column, so a version, region, customer or endpoint that the slow requests have in common shows up at once.
3. Call `search_traces` for the slowest traces, then `get_trace` with one of their trace ids. The span that takes most of the time, or many short spans one after another, is where the time went.
4. When a column you need is not in the query, `get_dataset_columns` lists what the dataset has.
