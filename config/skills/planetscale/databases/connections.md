---
name: planetscale_connections
when: Finding why an app cannot connect to a PlanetScale database, runs out of connections, or fails to authenticate
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_get_postgres_logs, planetscale_execute_read_query, planetscale_get_branch]
references: [postgres/ps-connections.md, postgres/ps-connection-pooling.md, postgres/pgbouncer-configuration.md, postgres/process-architecture.md, mysql/connection-management.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Find the exact error the app saw, from its own logs, before anything else. The error decides the cause:
   - too many clients already: the app opens direct connections past the limit. Apps should connect through PgBouncer on port 6432, and port 5432 is for migrations and admin work.
   - password authentication failed: a Postgres role on PlanetScale belongs to one branch, so a role from another branch, or a role deleted since, fails. Its name looks like role.branch_id.
   - SSL connection is required: the connection string is missing sslmode=verify-full.
3. For Postgres, count connections by state with `planetscale_execute_read_query`: SELECT state, count(*) FROM pg_stat_activity GROUP BY state. Many idle in transaction sessions mean the app holds transactions open, which also blocks vacuum.
4. Call `planetscale_get_postgres_logs` with `from` and `to` around the failures for what the server said, such as connection limits or authentication failures.
5. Call `planetscale_get_branch` when the app reached the wrong branch or a branch that is not ready.
6. Say which connections fail, the error, and the cause. Raising the connection limit hides a pooling problem, so recommend pooling first.
