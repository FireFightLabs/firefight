---
name: clickhouse_resources
when: Finding whether a ClickHouse Cloud service is short of memory or CPU, such as memory limit errors, slow queries under load, or replicas that fall over
tools: [resource_status, query_metrics, search_errors, search_logs, scale, scale_service]
references: [best-practices/agent-query-safety.md, best-practices/query-join-choose-algorithm.md]
---
1. Call `resource_status` for its replicas, the memory each replica may scale between and whether idle scaling is on.
2. Call `query_metrics` with `metrics` memory, cpu and requests over a range that starts well before the trouble. Each replica is its own series.
   - Memory climbing to the same ceiling on every replica, then falling, is queries running out of memory. Compare it with `search_errors` for MEMORY_LIMIT_EXCEEDED at the same minutes.
   - CPU at the replicas' limit together with more requests is load, and the service needs more replicas or more memory per replica.
   - One replica far above the others is one heavy query or client. Read `search_logs` with `stream` requests for that replica's queries with the most memory used.
   - Compare against what normal looks like for the service on the resource map before calling a reading high.
3. Say what is short, since when, and whether a query or the load is behind it. When a query is behind it, fixing the query comes first, since more memory only delays the next failure.
4. When the load itself has grown, propose `scale` for the service. `instances` sets its replicas, and `plan` the memory each replica scales between in GiB, one size such as 32 or a range such as 16-64, a multiple of 4 from 8 to 356. To keep a service awake or let it idle sooner, call `scale_service` with `idleScaling` and `idleTimeoutMinutes`. Each asks the person once, and its answer says how the service scaled before and how it scales now.
5. Scaling needs a connection made with a ClickHouse Cloud API key whose role may manage scaling. On a connection signed in instead, `scale_service` says so, and the person connects ClickHouse again with a key or scales the service in the ClickHouse Cloud console.
