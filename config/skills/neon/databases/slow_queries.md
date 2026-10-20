---
name: neon_slow_queries
when: Finding why a Neon database answers slowly, or which queries load it most
tools: [resource_status, query_metrics, search_errors, inspect_database, explain_sql_statement, scale]
---
1. Call `resource_status` for the branch. A compute at the top of its autoscaling range is short of CPU or memory, and one that suspends often starts each time with a cold cache. `query_metrics` for the project, with `cpu_time`, shows its compute time hour by hour from Neon's consumption history, where a step up points at when the load grew. It needs a connection made with an organization API key and a plan that keeps consumption history, and says so otherwise.
2. Call `search_errors` for the branch, or for one compute. It reads pg_stat_statements through `list_slow_queries`, slowest on average first, with how often each ran. When it says the extension is missing, tell the person it is needed and that adding it is their call.
3. Call `inspect_database` with `check` outliers for the queries that took the most time in total, and calls for the most frequent. A fast query called millions of times can load the database more than one slow query.
4. Call `inspect_database` with `check` seq-scans and unused-indexes. A large table read by sequential scans usually lacks an index for its filter.
5. Call `inspect_database` with `check` lfc-hit-rate and working-set. Neon caches data on the compute, and a working set larger than that cache sends reads to storage, which is slower.
6. Call `explain_sql_statement` with `analyze` true for the worst query, to see where its time goes. Neon marks this tool as able to change the database, so it asks before running.
7. Say which queries are slow and why, and the index or change that would help. Never create an index without the person's say.
8. When the compute is short of CPU or memory and the queries are already sound, `scale` on the compute with `plan` a size in compute units, such as 4, or an autoscaling range, such as 1-8, resizes it. Neon restarts the compute to apply it and open connections drop, so say so before asking for it.
