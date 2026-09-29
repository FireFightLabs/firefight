---
name: planetscale_slow_queries
when: Finding why a PlanetScale database, or the queries against it, are slow
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_get_insights, planetscale_get_branch_schema, planetscale_list_schema_recommendations, planetscale_execute_read_query]
references: [postgres/ps-insights.md, postgres/indexing.md, postgres/query-patterns.md, postgres/optimization-checklist.md, mysql/explain-analysis.md, mysql/query-optimization-pitfalls.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Call `planetscale_get_insights` for the production branch with `from` and `to` around when it was slow. It ranks query patterns by total time, time per run, rows read and how often they run, and flags anomalies. A range wider than 25 hours must start on the hour.
3. Read the ranking:
   - Many rows read for each row returned means the query scans instead of using an index.
   - The most total time is where a fix helps most, even when each run is quick.
   - A pattern that appeared or slowed right after a deploy points at that deploy's code or migration.
4. For the top pattern, read its table with `planetscale_get_branch_schema` and check `planetscale_list_schema_recommendations`, which suggests indexes from production traffic.
5. Confirm with `planetscale_execute_read_query` running EXPLAIN on the query. It shows whether an index is used. Never run EXPLAIN ANALYZE on a statement that writes, since it runs it.
6. Say which query is slow, on which table, the numbers behind it, and the index or rewrite that would help. Adding or dropping an index is a change for the team to make, never a step to take here.
