---
name: planetscale_query_errors
when: Finding which queries fail on a PlanetScale database, and why
tools: [planetscale_list_query_error_patterns, planetscale_list_query_error_executions, planetscale_get_postgres_logs]
---
1. Call `planetscale_list_query_error_patterns` for the branch and the window. Each error comes with how often it happened and when it was last seen.
2. For the pattern that matches, call `planetscale_list_query_error_executions` with its `error_fingerprint` to see the failing statements, their tables and the full error.
3. For a Postgres database, `planetscale_get_postgres_logs` with `from` and `to` shows what the server logged, such as running out of connections or waiting on locks. It does not work for MySQL databases.
4. A window longer than 25 hours falls back to the last 24 hours on these tools, so ask for the window you mean.
