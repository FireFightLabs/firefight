---
name: clickhouse_slow_queries
when: Finding why queries against a ClickHouse Cloud service are slow or time out
tools: [search_logs, query_metrics, run_select_query, list_tables]
references: [best-practices/agent-query-safety.md, best-practices/schema-pk-filter-on-orderby.md, best-practices/query-join-filter-before.md, best-practices/insert-optimize-avoid-final.md, best-practices/query-index-skipping-indices.md]
---
1. Call `search_logs` with `stream` requests over the slow period. Each line is one query that finished or failed, with how long it took, how many rows it read and the start of its text. The slowest that read the most rows are the suspects.
2. Call `query_metrics` with `metrics` requests, cpu and memory over a range that starts well before. Slow queries with CPU near the replicas' limit is load, and the same queries were fast before. Slow queries on steady load is the queries themselves or a change in the data.
3. For the suspect query, read its table with `list_tables` for the database it names. A filter that does not use the leading columns of the table's ORDER BY reads the whole table, and so does FINAL. A JOIN whose right side is large holds it all in memory.
4. To confirm, run `run_select_query` with EXPLAIN indexes = 1 before the query, which shows how many parts and granules the primary key let it skip. The server runs only SELECT, so when it refuses EXPLAIN, compare the rows the query read with the rows it returned in step 1 instead. Never run a large query only to time it. Always bound a query you write yourself with a LIMIT and a filter on the table's time column.
5. Say which query is slow, the rows it read against what it returned, and the change that would help, such as filtering on the sorting key or a skipping index. Changing a table is for the team to do.
