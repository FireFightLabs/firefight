---
name: clickhouse_failing_queries
when: Finding why queries or inserts against a ClickHouse Cloud service fail with errors
tools: [search_errors, search_logs, resource_status, query_metrics]
references: [best-practices/agent-query-safety.md, best-practices/insert-batch-size.md, best-practices/insert-async-small-batches.md]
---
1. Call `search_errors` with `start` and `end` around the failures. Each error comes with its name, code, how often it happened, when it began and an example.
2. Match the name:
   - MEMORY_LIMIT_EXCEEDED: a query needed more memory than a replica allows. Load the clickhouse_resources skill.
   - TIMEOUT_EXCEEDED: a query ran past its time limit. Load the clickhouse_slow_queries skill.
   - TOO_MANY_PARTS: inserts arrive faster than ClickHouse merges them. Load the clickhouse_inserts skill.
   - UNKNOWN_TABLE, UNKNOWN_IDENTIFIER or a type mismatch: the query expects a table or column that is not there, which usually follows a deploy or a migration.
   - AUTHENTICATION_FAILED or ACCESS_DENIED: the client's user or its grants changed.
3. Call `search_logs` with `stream` requests and `text` set to the error's name for the failing queries themselves, which user sent them and from which query kind.
4. Call `search_logs` with `stream` app and `text` set to the error's name or code for what the server printed around them.
5. Call `resource_status`. A service that was stopped, idle or upgrading explains failures for a short while.
6. Say which error, since when, which queries or clients it hits and the evidence for why.
