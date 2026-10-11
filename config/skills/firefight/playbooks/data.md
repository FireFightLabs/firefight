---
name: data
when: A database's health, connections, locks, replication or disk, a query against production data, a change to production rows, a migration, or backups and restores
tools: [resource_status, run_key_query, query_metrics, what_changed, get_resource]
---
What good looks like: data is safe, recoverable and correct. Databases are healthy and their limits are known before they are hit. Changes to production data are rare, deliberate, counted and owned.

How to approach it:
1. Read before you touch. Count the rows a change would affect, and check what else the same condition catches. A pattern that looks like test data often matches real customers too.
2. Before writing a query against an application's own tables, read their names and columns from the application's repository on the connected code host (db/schema.rb, db/structure.sql, prisma/schema.prisma, its models or its migrations, found with the code host's code skill). When no repository holds them, read the database's own schema for those tables first, then write the query.
3. Look at the database's health as a whole: connections against the limit and who holds them, locks and long queries, replication lag, disk, slow query patterns. `resource_status` and `run_key_query` read how it stands against normal, and the database provider's own skills, such as postgresql_locks or planetscale_slow_queries, read the detail.
4. Read the primary first, since it is current. A replica can be behind, so stale data can look like lost data. Read a replica only when the primary is slow or refuses, and say the answer came from one.
5. Plan migrations so a rollback stays possible: add before you remove, backfill in batches, set lock timeouts on large tables.
6. Data changes need their owner. Know who owns the data, and get their agreement for anything that deletes or rewrites production rows.

What to check:
- Connection use by client or host, and recent changes to pool sizes (`what_changed`).
- Long running queries and the locks they hold.
- Replication lag and pending schema changes.
- The last successful backup and the last tested restore.

Trade-offs:
- Killing a long query frees a lock now but may lose work. Say whose query it is.
- A restore is the last resort. Prefer a targeted repair with a dry run first.

Done means: the database is healthy again or the risk is clearly stated, and any data change was counted, agreed by its owner, and verified afterwards.

Proactive habits:
- Watch disk, connections and lag trends before they hit limits.
- Check that backups exist and that a restore has been tested recently.
