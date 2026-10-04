---
name: clickhouse_inserts
when: Finding why inserts into a ClickHouse Cloud service fail or data arrives late, including TOO_MANY_PARTS errors and ClickPipes that stopped
tools: [search_errors, search_logs, list_clickpipes, get_clickpipe, run_select_query]
references: [best-practices/insert-batch-size.md, best-practices/insert-async-small-batches.md, best-practices/insert-mutation-avoid-update.md, best-practices/insert-mutation-avoid-delete.md]
---
1. Call `search_errors` around when data stopped arriving. TOO_MANY_PARTS means inserts come in many small batches faster than ClickHouse merges them, and ClickHouse then refuses new ones until merges catch up.
2. Call `search_logs` with `stream` requests and `text` INSERT for how often inserts arrive and how many rows each carries. Thousands of inserts of a few rows each is the pattern ClickHouse's guides warn against, and batching them or using asynchronous inserts is the fix for the team.
3. When data arrives through ClickPipes, call `list_clickpipes` for the service and `get_clickpipe` for the one that feeds the table. Its state and last error say whether it is running, paused or failing.
4. To see how many parts a table holds now, run `run_select_query` on system.parts with a filter on the table and active = 1, counting rows by partition.
5. Say where inserts fail, since when and why, and what the team can change in how they insert.
