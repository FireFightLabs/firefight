---
name: azure_postgresql
when: An Azure PostgreSQL flexible server is slow, out of connections or storage, or not ready
tools: [resource_status, query_metrics, search_logs, restart]
---
1. Call `resource_status` for its state, version, size, storage and high availability. A state other than ready, such as updating, stopping or stopped, explains a lot. Updating is usually maintenance or a change someone made.
2. Call `query_metrics` with `metrics` cpu, memory, disk and tcp_connections. Storage near full makes the server read only to protect itself. Active connections near the server's limit make new ones fail.
3. Read the server's log with `search_logs`, which Azure keeps only when a diagnostic setting sends it to Log Analytics. Look for too many connections, out of memory, canceled statements and errors from the apps.
4. Too many connections usually comes from the apps that use it, such as a deploy that opened a new pool per instance, so look at their recent deploys and replica counts before the server.
5. A restart with `restart` drops every connection while the server comes back. Offer it only for a server stuck in a bad state while its load is normal. There is no undo.
6. Say what is wrong, the evidence, and the fix: in the apps, more storage, a bigger size, or a restart.
