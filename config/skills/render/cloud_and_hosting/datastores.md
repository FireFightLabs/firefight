---
name: render_datastores
when: A Postgres database or Key Value instance on Render is unavailable, slow, refuses connections, or is in maintenance
tools: [resource_status, query_metrics, search_logs, list_resources]
references: [debug/database-debugging.md, postgres/connection-guide.md, postgres/performance-tuning.md, postgres/backup-and-recovery.md, keyvalue/troubleshooting.md, keyvalue/connection-examples.md]
---
1. Call `resource_status`. Its status is available when the datastore works. Unavailable, recovery_in_progress, recovery_failed or config_restart mean Render is acting on it, and maintenance_in_progress or a maintenance line means a scheduled change is running. A Postgres database also shows whether high availability is on, its read replicas, its disk and whether the disk grows on its own.
2. Call `query_metrics` with `metrics` cpu, memory and tcp_connections for the window. Connections at the plan's limit make new ones fail, which an app reports as refused or timed out connections. Postgres on Render offers connection pooling, shown in `resource_status`.
3. Read the datastore's own logs with `search_logs`, `stream` app, for errors such as too many connections, out of disk or out of memory.
4. A Postgres database can be restarted with the restart capability, which the render_fixes skill covers. A Key Value instance cannot be restarted through Render's API.
5. A full disk, a bigger plan or a failover are changes for a person in Render's dashboard. Say which, and why.
