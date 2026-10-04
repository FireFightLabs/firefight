---
name: neon_locks
when: Finding why queries on a Neon database hang, wait on each other, or deadlock
tools: [inspect_database, run_sql]
---
1. Call `inspect_database` with `check` stalled-queries. It groups active queries running longer than 30 seconds with what they wait on and who blocks them, oldest first.
2. Call `inspect_database` with `check` locks for the locks held, the query holding each and how long.
3. Call `inspect_database` with `check` long-running-queries. A transaction left open holds its locks until it ends, and blocks vacuum too.
4. When one session blocks many, find what it is with `run_sql`, `sql` SELECT pid, usename, application_name, state, xact_start, query FROM pg_stat_activity WHERE pid = the blocker.
5. Call `inspect_database` with `check` vacuum-stats and bloat when tables kept growing while the locks were held.
6. Say which session blocks, what it runs and since when. Ending a session with pg_terminate_backend rolls back its work, so it is the person's decision.
