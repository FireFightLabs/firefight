---
name: northflank_crashes
when: Finding why a Northflank service or database keeps restarting, crashes, fails to start or is failing health checks
tools: [describe_resource, list_containers, query_metrics, search_logs, list_deployments]
---
1. Call `list_containers`. Each restart starts a new container, so several started in a short time, or any failed, is the restart loop. Note when each one stopped.
2. Call `describe_resource` for the plan, ephemeral storage and health checks.
3. Match the cause:
   - Out of memory: call `query_metrics` with `metrics` memory around each stop. Memory climbing to a flat top just before a container ends is the container running out and being killed. Northflank's own alerts treat 90% for a short while as a spike and for 5 minutes as sustained.
   - Eviction: a container that wrote more than its ephemeral storage is evicted. Suspect it when the app writes files or unpacks something large, and storage use climbs before the stop.
   - Failing health check: a liveness probe that fails its threshold restarts the container, a readiness probe only takes it out of traffic, and a startup probe that fails keeps it from ever starting. A probe whose initial delay is shorter than the app's boot time fails on every start.
   - The process exits: the app itself stopped, such as a missing setting or a failed connection at boot. The last lines it printed say why.
4. Read those last lines with `search_logs`, `type` runtime, `start` a minute before a container stopped and `end` just after it.
5. Call `list_deployments`. Restarts that began with a deployment point at that change, such as a new setting the app cannot read or a heavier build.
