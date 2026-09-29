---
name: northflank_resources
when: Checking whether a Northflank service or database is short of CPU, memory or disk, or keeps restarting
tools: [list_resources, query_metrics, search_logs]
---
1. Call `list_resources` for the exact name, and whether it is a service or a database.
2. Call `query_metrics` on that `resource` with `metrics` cpu and memory, and diskUsage for a database. Each container is its own series, so one container near its limit shows even when the others look fine.
3. Memory that climbs to a flat top and then drops, with a new container in the series after it, is a restart. Read what the app printed just before it with `search_logs`, `type` runtime, and `start` and `end` around the drop.
