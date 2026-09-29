---
name: planetscale_slow_queries
when: Finding why a PlanetScale database, or the queries against it, are slow
tools: [planetscale_list_databases, planetscale_get_insights, planetscale_get_branch_schema, planetscale_list_schema_recommendations]
---
1. When the person did not name the database, find its organization and name with `planetscale_list_databases`. Production is usually the main branch.
2. Call `planetscale_get_insights` for that branch with `from` and `to` around when it was slow. It ranks the slowest queries, the ones taking the most time in total, reading the most rows and the least efficient.
3. For a query that reads far more rows than it returns, read its table with `planetscale_get_branch_schema` and check `planetscale_list_schema_recommendations`, which suggests indexes from production traffic.
4. Name the query, its table and the numbers behind it. A range wider than 25 hours must start on the hour.
