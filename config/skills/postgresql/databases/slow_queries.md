---
name: postgresql_slow_queries
when: Finding why a Postgres database answers slowly, or which queries load it most
tools: [current_activity, search_errors, database_errors, run_query, explain_query, table_health, describe_table]
references: [postgres/query-patterns.md, postgres/indexing.md, postgres/index-optimization.md, postgres/optimization-checklist.md]
---
1. Call `current_activity` for the queries running longest now.
2. Call `search_errors` for the database, or `database_errors` when it is not on the map yet, for the queries that took the most time in all, with how often each ran and its average time, from pg_stat_statements. When it says the extension is not installed, say so, and that adding it is the person's call. For a column the answer leaves out, read pg_stat_statements with `run_query`.
3. Call `table_health` for tables read by many sequential scans and few index scans. A large table read that way usually lacks an index for its filter.
4. Call `describe_table` for the tables the slow query reads, to see their indexes.
5. Call `explain_query` with the query in `sql`. Set `analyze` true only for a read, since it runs the query, to see real timings per step.
6. Say which queries are slow and why, and the index or change that would help. This connection only reads, so the change is the person's to make.
