---
name: turso_slow_queries
when: Finding why queries against a Turso database are slow, or why it reads far more rows than expected
tools: [database_analytics, read_database, get_database]
references: [help/usage-and-billing.md, cloud/limitations.md]
---
1. Call `database_analytics` for the database over the slow period. It ranks the top queries by how often they ran and how long they took.
2. A slow query that runs often usually scans its table. To confirm, run `read_database` with EXPLAIN QUERY PLAN before the query. SCAN on a large table means no index is used, and SEARCH means one is. When the tool refuses anything but a SELECT, read the table's indexes instead, as in step 3.
3. Read the table's indexes with `read_database` on sqlite_schema, filtered to the table. Reading this table costs no row reads.
4. Call `get_database` for its region. Clients far from the primary region wait longer for every write.
5. Say which query is slow, the rows it reads and the index or rewrite that would help. Adding an index is for the team to do, and it reads every row of the table once while it is built.
