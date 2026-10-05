---
name: google_cloud_cloud_sql
when: A Cloud SQL database is slow, refuses connections, runs out of disk, or its instance is not running
tools: [resource_status, query_metrics, search_logs, restart]
references: [sql/postgres-diagnose-issues.md, sql/mysql-diagnose-issues.md, sql/postgres-manage-connections.md, sql/postgres-system-insights.md, sql/postgres-start-stop-restart.md, sql/mysql-start-stop-restart.md]
---
1. Call `resource_status` for its engine, state, tier and availability. A state other than runnable explains a lot: maintenance and failover are Google's work, suspended usually means billing, and an activation policy of never means it was stopped on purpose.
2. Call `query_metrics` with `metrics` cpu, memory, disk and tcp_connections. CPU near its ceiling makes every query slow. Disk near full stops writes. Connections near the engine's limit make new ones fail.
3. Read the database's own log with `search_logs`. Look for too many connections, out of memory, deadlocks and slow statements.
4. Too many connections usually comes from the apps that use it, such as a deploy that opened a new pool per instance, so look at their recent deploys and instance counts before the database.
5. A restart with `restart` drains the connections and stops the instance, then starts it again, which can take several minutes. It keeps its addresses. Offer it only for an instance stuck in a bad state while its load is normal, since it fixes nothing that is caused by load. There is no undo.
6. Say what is wrong, the evidence, and whether the fix is in the apps, a bigger tier or more disk, or a restart.
