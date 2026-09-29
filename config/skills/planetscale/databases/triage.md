---
name: planetscale_triage
when: Starting on anything wrong with a PlanetScale database, before knowing what kind of problem it is
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_get_database, planetscale_list_branches, planetscale_get_branch]
references: [postgres/monitoring.md, postgres/ps-insights.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`.
2. Call `planetscale_get_database`. Whether it is Postgres or MySQL decides everything after this. Postgres has server logs and the pg_stat views to query. MySQL on PlanetScale runs on Vitess, and the server log tool does not work for it.
3. Call `planetscale_list_branches`. Production is usually the main branch. Answer about the branch the application uses, since development branches have their own data and traffic.
4. Call `planetscale_get_branch` for its state, and whether it has replicas that reads may be served from.
5. Then load the skill that fits what was reported: planetscale_slow_queries, planetscale_query_errors, planetscale_connections or planetscale_locks.
