---
name: postgresql_slow_queries
when: Finding why a Postgres database answers slowly, or which queries load it most
tools: [current_activity, run_query, explain_query, table_health, describe_table]
references: [postgres/query-patterns.md, postgres/indexing.md, postgres/index-optimization.md, postgres/optimization-checklist.md]
---
1. Call `current_activity` for the queries running longest now.
2. When pg_stat_statements is installed, read the costliest queries with `run_query`, `sql` SELECT calls, round(total_exec_time) AS total_ms, round(mean_exec_time) AS mean_ms, left(query, 200) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10. When it is not, say so, and that adding it is the person's call.
3. Call `table_health` for tables read by many sequential scans and few index scans. A large table read that way usually lacks an index for its filter.
4. Call `describe_table` for the tables the slow query reads, to see their indexes.
5. Call `explain_query` with the query in `sql`. Set `analyze` true only for a read, since it runs the query, to see real timings per step.
6. Say which queries are slow and why, and the index or change that would help. This connection only reads, so the change is the person's to make.
