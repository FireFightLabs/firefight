---
name: aws_rds
when: Finding why an RDS database is slow, unavailable, out of storage or out of connections
tools: [resource_status, query_metrics, cloudwatch_metrics, search_logs, logs_insights_query]
references: [rds/proxy-pinning-postgresql.md, rds/proxy-pinning-mysql.md, rds/proxy-advisor-workflow.md]
---
1. Call `resource_status`. Its status says what RDS is doing: available is serving, and backing-up, modifying, rebooting, maintenance or upgrading are changes in progress that can slow or interrupt it. storage-full means it has no space left. Read the events of the last day for a failover, a reboot, a maintenance window or a change someone applied, and the pending changes for one waiting for the next window.
2. Call `query_metrics` over the window, which reads CPUUtilization, DatabaseConnections, FreeableMemory and FreeStorageSpace when `metrics` is left out. `cloudwatch_metrics` also reads ReadLatency and WriteLatency:
   - Connections climbing to a flat top: the app runs out of connections. The engine's max_connections parameter sets the top, and an app that opens a connection per request without a pool reaches it under load. RDS Proxy pools them, and the proxy guides say when a session gets pinned to one connection.
   - CPU near 100% with latency rising: a query or a load the instance class cannot carry.
   - FreeStorageSpace falling to zero: the database stops taking writes. Storage autoscaling grows it only up to its maximum, which `resource_status` shows.
   - FreeableMemory near zero with ReadLatency rising: the working set no longer fits in memory.
3. Read the database's own logs with `search_logs`. RDS writes them to CloudWatch Logs only for the log types exported on the database, which `resource_status` lists. With none exported, say that logs can be exported in RDS, such as the error log, the slow query log or the PostgreSQL log.
4. Count errors over time with `logs_insights_query` on an exported log group, such as filter @message like /ERROR/ | stats count(*) by bin(5m).
5. Changes to an RDS database, such as a reboot, a failover, a new instance class or more storage, are steps for a person in the AWS console, since each one can interrupt the database. Say what to change and what it interrupts.
