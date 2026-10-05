---
name: newrelic_slow_transactions
when: Finding why a service New Relic watches is slow, times out, or its response time rose
tools: [analyze_transactions, analyze_golden_metrics, execute_nrql_query, get_distributed_trace_details, recent_deploys, list_change_events, search_logs]
references: [traces/SKILL.md, traces/queries.md, nrql/queries.md]
---
1. Call `analyze_golden_metrics` for the service over a range that starts well before it slowed, and find when response time began to rise and whether throughput rose with it. Slowness that follows a rise in traffic points at load.
2. Call `analyze_transactions` for the same range. It ranks the slowest and most error prone transactions with their 95th and 99th percentile times.
   - Every transaction slowing together points at something they share: a host, a database, or load.
   - One transaction slowing alone points at its own code or what it calls.
3. For the slow transaction, call `execute_nrql_query` on Transaction for the service's appName and that name, selecting duration, databaseDuration, externalDuration, queueDuration and trace.id, ordered by duration. Time in databaseDuration is the database, externalDuration is calls to other services, and queueDuration is the wait before the service began, all in seconds.
4. Call `get_distributed_trace_details` for the trace of a slow one. The longest span is where the time went.
5. Call `recent_deploys` or `list_change_events` around the minute it began, and `search_logs` with timeout for calls that gave up.

An average hides a slow tail, so read percentiles, and narrow the range to see a short spike.
