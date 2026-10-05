---
name: axiom_latency
when: Finding why a service whose traces go to Axiom is slow, times out, or its latency rose
tools: [search_traces, querydataset, query_metrics]
references: [sre/query-patterns.md, sre/apl-functions.md, sre/metrics.md]
---
1. Call `querydataset` on the traces dataset for the service's root spans (isnull(parent_span_id)) with percentiles_array(duration, 50, 95, 99) over bin_auto(_time), from well before it slowed. Find the minute it began and whether the median rose too, or only the slowest requests.
2. Break the same query down by name to see whether every endpoint slowed or one.
   - Every endpoint slowing together points at something they share: a database, a dependency or load.
   - One endpoint slowing alone points at its own code or what it calls.
3. Call `query_metrics` with requests to see whether traffic rose when it slowed.
4. Call `search_traces` for the slowest traces, then `querydataset` with where trace_id equals one of them. The span that takes most of the time is where it went. duration is a timespan, so compare it with literals such as 500ms.
