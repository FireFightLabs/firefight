---
name: neon_slow_queries
when: Finding why a Neon database answers slowly, or which queries load it most
tools: [resource_status, list_slow_queries, inspect_database, explain_sql_statement]
---
1. Call `resource_status` for the branch. A compute at the top of its autoscaling range is short of CPU or memory, and one that suspends often starts each time with a cold cache.
2. Call `list_slow_queries` with `project_id` and `branch_id`. It reads pg_stat_statements, slowest first. When it says the extension is missing, tell the person it is needed and that adding it is their call.
3. Call `inspect_database` with `check` outliers for the queries that took the most time in total, and calls for the most frequent. A fast query called millions of times can load the database more than one slow query.
4. Call `inspect_database` with `check` seq-scans and unused-indexes. A large table read by sequential scans usually lacks an index for its filter.
5. Call `inspect_database` with `check` lfc-hit-rate and working-set. Neon caches data on the compute, and a working set larger than that cache sends reads to storage, which is slower.
6. Call `explain_sql_statement` with `analyze` true for the worst query, to see where its time goes. Neon marks this tool as able to change the database, so it asks before running.
7. Say which queries are slow and why, and the index or change that would help. Never create an index without the person's say.
