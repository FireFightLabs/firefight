---
name: postgresql_connections
when: Finding why an app cannot connect to a Postgres database or runs out of connections
tools: [database_status, current_activity, run_query]
references: [postgres/process-architecture.md, postgres/pgbouncer-configuration.md, postgres/memory-management-ops.md]
---
1. Call `database_status`. Connections near max_connections mean new ones are refused with too many clients already. A server up for only minutes restarted and dropped every connection.
2. Call `current_activity`. Many idle sessions mean the app keeps connections it does not use, and many idle in transaction sessions mean it opens transactions and does not finish them.
3. Group the sessions by who holds them with `run_query`, `sql` SELECT usename, application_name, client_addr, state, count(*) FROM pg_stat_activity GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC. One application holding most of them is the one to fix.
4. Say which client holds the connections and in what state. Every connection is its own server process with its own memory, so putting a pooler such as PgBouncer in front comes before raising max_connections.
