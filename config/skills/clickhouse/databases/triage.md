---
name: clickhouse_triage
when: Starting on anything wrong with a ClickHouse Cloud service, such as slow or failing queries, inserts falling behind or the service being unreachable, before knowing what kind of problem it is
tools: [resource_status, search_errors, query_metrics, search_logs, get_services_list, get_organizations]
references: [best-practices/agent-connect-mcp.md, best-practices/agent-query-safety.md]
---
ClickHouse Cloud's server only reads, so every tool here is safe to call. `resource_status`, `search_logs`, `search_errors` and `query_metrics` take a service by its name on the resource map and read its system tables across every replica. ClickHouse's server must be switched on for each service in the ClickHouse Cloud console, under the service's Connect button and then MCP. A call refused for one service while others answer usually means it is off there, and only a person with that permission can switch it on.

1. When the person did not name the service, find it with `get_organizations` and `get_services_list`, or on the resource map.
2. Call `resource_status`. Its state says what ClickHouse is doing: running, idle or stopped when it scaled to zero, awaking while it starts again, degraded or failed when it is broken. A service waking from idle takes 10 to 20 seconds for its first query, and a timeout then is expected, so try once more before treating it as an outage. Note its replicas, memory per replica and whether it is read only.
3. Call `search_errors` over a range that starts before the trouble. The errors ClickHouse raised, grouped by name, say which kind of problem this is.
4. Then load the skill that fits: clickhouse_slow_queries when queries are slow or time out, clickhouse_failing_queries when they fail, clickhouse_resources for memory, CPU or replicas under strain, and clickhouse_inserts when inserts fail or data arrives late.
