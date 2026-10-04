---
name: postgresql_locks
when: Finding why queries on a Postgres database hang, wait on each other or deadlock
tools: [current_activity, database_status, run_query]
references: [postgres/mvcc-transactions.md]
---
1. Call `current_activity`. Its blocked list names each waiting session and the sessions blocking it.
2. Look up what a blocker holds with `run_query`, `sql` SELECT l.pid, l.locktype, l.mode, l.granted, c.relname FROM pg_locks l LEFT JOIN pg_class c ON c.oid = l.relation WHERE l.pid = the blocker.
3. Call `database_status` for deadlocks since statistics were reset and the oldest open transaction. A transaction left open holds its locks until it ends.
4. Say which session blocks, what it runs and since when. Ending it with pg_terminate_backend rolls its work back, and this connection cannot, so it is the person's decision.
