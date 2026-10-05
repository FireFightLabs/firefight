---
name: upstash_redis
when: Finding why an Upstash Redis database is slow, refuses commands, runs out of room or drops connections
tools: [resource_status, query_metrics, redis_list_backups]
references: [redis/error-handling.md, redis/pipeline-optimization.md, redis/batching-operations.md, redis/ttl-expiration.md]
---
1. Call `resource_status` for its plan, state, eviction, regions and limits: the most clients, commands per second, request size and data size it takes.
2. Call `query_metrics` with `metrics` requests, tcp_connections and disk over a range that starts before the trouble.
   - Commands per second at the database's limit means it refuses the rest, so the client sees errors or retries.
   - Connections climbing toward the client limit is a client opening a connection per request and not closing it.
   - Data size near the limit with eviction off means writes are refused. With eviction on, keys are removed to make room, which reads as data going missing.
3. Compare against what normal looks like for the database on the resource map before calling a reading high.
4. When data went missing, call `redis_list_backups` for whether there is a backup from before.
5. Say what is at its limit, since when and which client or pattern is behind it. Changing the plan, eviction or limits is for a person to do in the Upstash console.
