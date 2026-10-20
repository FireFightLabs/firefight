---
name: upstash_redis
when: Finding why an Upstash Redis database is slow, refuses commands, runs out of room or drops connections, or bringing back its data from a backup
tools: [resource_status, query_metrics, redis_list_backups, redis_create_backup, rollback, restore_redis_backup]
references: [redis/error-handling.md, redis/pipeline-optimization.md, redis/batching-operations.md, redis/ttl-expiration.md]
---
1. Call `resource_status` for its plan, state, eviction, regions and limits: the most clients, commands per second, request size and data size it takes.
2. Call `query_metrics` with `metrics` requests, tcp_connections and disk over a range that starts before the trouble.
   - Commands per second at the database's limit means it refuses the rest, so the client sees errors or retries.
   - Connections climbing toward the client limit is a client opening a connection per request and not closing it.
   - Data size near the limit with eviction off means writes are refused. With eviction on, keys are removed to make room, which reads as data going missing.
3. Compare against what normal looks like for the database on the resource map before calling a reading high.
4. When data went missing, call `redis_list_backups` for whether there is a completed backup from before.
5. To bring it back, propose `rollback` on the database with `to` set to that backup's id. Restoring replaces everything the database holds with what the backup holds, so what was written since the backup is lost. When anything since may be needed, take a backup of the database as it is now with `redis_create_backup` first and say so. It asks the person once. It needs a connection made with a Developer API key, and on a connection signed in instead it says how to connect again with one.
6. Say what is at its limit, since when and which client or pattern is behind it. Changing the plan, eviction or limits is for a person to do in the Upstash console.
