---
name: supabase_slow_queries
when: Finding why a Supabase database answers slowly, or which queries load it most
tools: [get_advisors, execute_sql, search_logs, list_tables]
references: [postgres/monitor-pg-stat-statements.md, postgres/monitor-explain-analyze.md, postgres/query-missing-indexes.md, postgres/schema-foreign-key-indexes.md, postgres/security-rls-performance.md, postgres/data-n-plus-one.md, postgres/monitor-vacuum-analyze.md]
---
1. Call `get_advisors` with `type` performance. It names unindexed foreign keys, unused indexes and row level security policies that run once per row, each with a link to the fix.
2. Read the costliest queries with `execute_sql`, `query` SELECT calls, round(total_exec_time) AS total_ms, round(mean_exec_time) AS mean_ms, left(query, 200) AS query FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10. When the extension is missing, say it is needed and that adding it is the person's call.
3. Call `search_logs` with `text` duration around the slowdown for statements Postgres logged as slow.
4. Call `list_tables` for the tables those queries read, to see their size and indexes.
5. Run the worst query through `execute_sql` with EXPLAIN in front of it to see its plan. EXPLAIN ANALYZE runs it for real, so only do that for a read.
6. Say which queries are slow and why, and the index or change that would help. A schema change goes through a migration the person approves, never straight from here.
