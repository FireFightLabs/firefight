---
name: northflank_databases
when: Finding why a database running on Northflank, such as Postgres, MySQL, Redis or MongoDB, is failing, slow or unreachable
tools: [resource_status, list_containers, query_metrics, search_logs]
---
1. Call `resource_status` for the database. Its status says what Northflank is doing to it: running, paused, scaling, upgrading, backup or restore while work is under way, and failed, error or errorAllocating when it is broken. Work under way explains a short outage.
2. Note the replicas, storage, plan, network access and secret rotation. A secret rotation changes the database's credentials, and an app still holding the old ones fails to connect.
3. Call `list_containers`. With replicas, one is the primary that takes writes and the others hold copies, and a stopped primary means a failover.
4. Call `query_metrics` with `metrics` cpu, memory and disk. Storage past half should be grown before it fills, and it can only grow.
5. Read what the database printed with `search_logs`, `stream` app, around the trouble: connection limits, running out of disk, or restarts.
6. When the app cannot connect but the database looks healthy, check the app's own logs for the connection error, and whether the database allows access from outside the project if the app runs elsewhere.
