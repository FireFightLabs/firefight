---
name: postgresql_triage
when: Starting on anything wrong with a Postgres database connected by its URL, before knowing what kind of problem it is
tools: [resource_status, database_status, current_activity]
references: [postgres/monitoring.md]
---
The connection reads one database, in its own read only session with a 10 second limit per statement. It is on the resource map by its name, and `resource_status` answers for it there. `database_status` answers the same for the connection directly.

1. Call `resource_status` for the database, or `database_status` when it is not on the map yet. It gives the version, size, how long the server has been up, connections against the limit, sessions waiting on locks, the oldest open transaction, and how close the database is to transaction ID wraparound.
2. Read the totals since statistics were reset. Deadlocks or rollbacks that keep climbing, or a cache hit rate well under 99 percent, each point at a kind of problem. A server up for minutes restarted recently, which explains dropped connections.
3. Call `current_activity` for what runs now: connections by state, the longest running queries and who blocks whom.
4. Then load the skill that fits: postgresql_connections when the app cannot connect, postgresql_slow_queries when it is slow, postgresql_locks when queries hang, postgresql_vacuum when tables grow or wraparound is near.
