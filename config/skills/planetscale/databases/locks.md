---
name: planetscale_locks
when: Finding what blocks queries on a PlanetScale Postgres database, such as locks, long transactions, or tables vacuum cannot keep up with
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_execute_read_query, planetscale_get_postgres_logs, planetscale_get_insights]
references: [postgres/mvcc-vacuum.md, postgres/mvcc-transactions.md, postgres/monitoring.md, postgres/storage-layout.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Find who blocks whom with `planetscale_execute_read_query`: SELECT pid, pg_blocking_pids(pid) AS blocked_by, state, now() - xact_start AS open_for, wait_event_type, left(query, 200) FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0 OR state = 'idle in transaction'. The session others wait on is the cause, and its query says what it is doing.
3. A transaction open for minutes or hours, often idle in transaction, holds its locks and stops vacuum from cleaning up. It is usually a job or a request that began a transaction and never finished.
4. Check tables vacuum is behind on with `planetscale_execute_read_query`: SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10. Many dead rows on a hot table slow every query on it.
5. Call `planetscale_get_postgres_logs` for lock waits and deadlocks around the time, and `planetscale_get_insights` for the query patterns that slowed when the blocking began.
6. Say which session blocks, what it runs, since when, and who is waiting. Ending a session is a change for the team to make, never a step to take here.
