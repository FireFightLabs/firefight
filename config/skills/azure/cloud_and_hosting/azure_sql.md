---
name: azure_sql
when: An Azure SQL database is slow, times out, has blocking or deadlocks, or refuses connections
tools: [resource_status, query_metrics, search_logs]
references: [sql/high-cpu-diagnose-troubleshoot.md, sql/understand-resolve-blocking.md, sql/troubleshoot-common-connectivity-issues.md, sql/troubleshoot-common-errors-issues.md]
---
1. Call `resource_status` for its status and service objective. A paused serverless database wakes on the first connection, which is slow. Scaling means its tier is changing.
2. Call `query_metrics` with `metrics` cpu and disk. CPU near its limit makes every query slow, and storage near full stops writes.
3. Read its errors, timeouts, blocks and deadlocks with `search_logs`, which Azure keeps only when a diagnostic setting sends them to Log Analytics.
4. High CPU usually comes from a few queries, often after a plan changed or data grew. Blocking comes from a transaction holding locks others wait on. Microsoft's guides show the queries that find each, which a person runs against the database.
5. Azure SQL has no restart. The fixes are in the queries, the indexes, or a bigger service objective, which a person changes in the portal.
6. Say what is wrong, the evidence, and the fix.
