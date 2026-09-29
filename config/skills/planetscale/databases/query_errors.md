---
name: planetscale_query_errors
when: Finding which queries fail on a PlanetScale database, and why
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_list_query_error_patterns, planetscale_list_query_error_executions, planetscale_get_postgres_logs]
references: [postgres/mvcc-transactions.md, mysql/deadlocks.md, mysql/row-locking-gotchas.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Call `planetscale_list_query_error_patterns` for the production branch and the window. Each error comes with how often it happened and when it was last seen.
3. For the pattern that matches what was reported, call `planetscale_list_query_error_executions` with its `error_fingerprint` to see the failing statements, their tables and the full error.
4. Read the error:
   - A deadlock or a serialization failure means two transactions fought over the same rows. It is usually solved in the code by locking rows in the same order or retrying.
   - A statement timeout or a canceled statement means a query ran past its limit, so look at it with the planetscale_slow_queries skill.
   - A missing column, table or type right after a deploy means the code and the schema are out of step, such as a migration that has not run.
5. For a Postgres database, `planetscale_get_postgres_logs` with `from` and `to` shows what the server logged around the errors. It does not work for MySQL databases.
6. A window longer than 25 hours falls back to the last 24 hours on these tools, so ask for the window you mean.
