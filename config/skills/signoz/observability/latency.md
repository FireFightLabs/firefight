---
name: signoz_latency
when: Finding why a service SigNoz watches is slow, times out, or its latency rose
tools: [signoz_get_service_top_operations, signoz_aggregate_traces, search_traces, signoz_get_trace_details]
references: [queries/SKILL.md, alerts/baseline-comparison.md]
---
1. Call `signoz_get_service_top_operations` for the service to rank its operations by their slowest calls.
2. Call `signoz_aggregate_traces` with aggregation p99 on duration_nano, the service, grouped by name, as a time_series from well before it slowed. Find the minute it began and whether every operation slowed or one.
   - Every operation slowing together points at something they share: a database, a dependency or load.
   - One operation slowing alone points at its own code or what it calls.
3. Call `search_traces` for the slowest spans, then `signoz_get_trace_details` with one trace id and a time range that holds it, since it looks back 6 hours unless told. The span that takes most of the time is where it went.
