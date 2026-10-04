---
name: turso_triage
when: Starting on anything wrong with a Turso database, such as failing or slow queries, refused writes or a missing database, before knowing what kind of problem it is
tools: [resource_status, list_databases, get_database, list_branches, database_analytics]
references: [help/usage-and-billing.md, cloud/limitations.md]
---
The connection is scoped to one organization, or to one group in it, chosen when it was connected, and a database outside that scope is not there. Databases are named by name. `read_database` only reads. Turso's other SQL tools write and are not used to investigate.

1. When the person did not name the database, call `list_databases`. A database branched from another shows its parent.
2. Call `resource_status`, or `get_database` for a database not on the resource map. Note whether reads or writes are blocked, its group, region and engine, delete protection and any allow rules on which addresses may connect.
3. Then load the skill that fits: turso_blocked when reads or writes are refused, turso_slow_queries when queries are slow or the database reads far more than expected, turso_lost_data when a database or rows are missing.
