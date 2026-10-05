---
name: neon_connections
when: Finding why an app cannot connect to a Neon database, waits long for its first query, or runs out of connections
tools: [resource_status, recent_deploys, inspect_database, run_sql, list_branch_computes]
---
1. Call `resource_status` for the branch the app uses. A compute that is disabled refuses connections, and one that is idle starts on the first connection, which can make the first query slow or time out in an app with a short connect timeout.
2. Call `recent_deploys` for the compute. Repeated start and suspend operations mean it scales to zero between bursts of traffic. A failed start compute operation explains connections that never succeed.
3. Find the exact error the app saw before anything else:
   - too many connections: the app connects to the compute directly. Neon pools connections through PgBouncer when the host in the connection string carries -pooler after the compute's id, and apps should connect that way.
   - password authentication failed: the role's password was reset, or the role belongs to another branch, since every branch has its own roles.
   - endpoint is disabled, or the compute is not found: the connection string names a compute that was disabled or deleted, or a branch that was removed or reset.
4. Call `run_sql` with `sql` SELECT state, count(*) FROM pg_stat_activity GROUP BY state, and `project_id` and `branch_id`, to count connections by state. Many idle in transaction sessions mean the app holds transactions open.
5. Call `inspect_database` with `check` long-running-queries for sessions holding connections a long time.
6. Say which connections fail, the error and the cause. Neon's limit on direct connections grows with the compute's size, so pooling is the first fix, before a larger compute.
