---
name: railway_crashes
when: A Railway service crashes, keeps restarting, runs out of memory, or a replica is down
tools: [resource_status, recent_deploys, query_metrics, search_logs]
references: [deployments/restart-policy.md, deployments/deployment-actions.md, deployments/scaling.md, observability/metrics.md]
---
A deployment is CRASHED when its process exited with a non-zero code. One that exits with 0 stays SUCCESS even though nothing runs.

1. Call `resource_status`. Read the replicas' states and the restart policy. Railway restarts a crashed replica on failure up to 10 times by default, only the replica that crashed, and once the restarts run out the deployment stays CRASHED until someone restarts or redeploys it.
2. Call `search_logs`, `stream` app, over the minutes before each crash. Read the last lines before the process stopped: an unhandled error, a failed connection to a database, or a missing variable.
3. Call `query_metrics` with `metrics` cpu and memory over the hours before. Memory that climbs and drops at each crash is the process running out of memory. Railway grows a replica's memory up to the plan's limit, so a crash at a steady high memory means it reached that limit.
4. Call `recent_deploys`. Crashes that started with a deployment point at its commit.
5. Say what stopped it, with the log line and the memory curve, and whether the crash loop is still going. For a fix, load railway_fixes: restart when the cause is passing, roll back when a deployment brought it, and scale when one replica cannot carry the load.
