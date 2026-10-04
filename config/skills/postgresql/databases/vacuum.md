---
name: postgresql_vacuum
when: Finding why Postgres tables keep growing, queries slow down over time, or the database warns about transaction ID wraparound
tools: [table_health, database_status, current_activity]
references: [postgres/mvcc-vacuum.md, postgres/storage-layout.md, postgres/wal-operations.md]
---
1. Call `table_health`. Tables with many dead rows against live ones, and an old or empty last autovacuum, are not being cleaned.
2. Call `database_status`. A transaction ID age past about 200 million is when autovacuum starts its forced runs, and Postgres stops taking writes before about 2 billion, so a figure climbing toward that is urgent.
3. Call `current_activity`. A long open transaction, or an idle in transaction session, keeps vacuum from removing any row it could still see.
4. Say which tables are behind and what holds vacuum back. Ending the long transaction and running VACUUM are the person's to do, since this connection only reads.
