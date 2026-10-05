---
name: supabase_connections
when: Finding why an app cannot connect to a Supabase database, or runs out of connections
tools: [resource_status, search_logs, execute_sql]
references: [postgres/conn-limits.md, postgres/conn-pooling.md, postgres/conn-idle-timeout.md, postgres/conn-prepared-statements.md]
---
1. Call `resource_status`. A paused project, status INACTIVE, refuses every connection until it is restored, which the person does from the dashboard or with restore_project.
2. Call `search_logs` around the failures with `text` connection for what Postgres said: too many clients, authentication failures, or connections ended by the server.
3. Find the error the app saw before anything else:
   - too many clients already, or remaining connection slots are reserved: the app opens direct connections past the limit. Apps that open many short connections, such as serverless functions, should connect through Supabase's pooler, Supavisor, in transaction mode on port 6543.
   - prepared statement does not exist: a client using prepared statements is behind the pooler in transaction mode, which does not keep them. Turn them off in the client.
   - password authentication failed: the database password was reset, or the connection string names the wrong project.
4. Count connections by state with `execute_sql`, `query` SELECT state, usename, count(*) FROM pg_stat_activity GROUP BY 1, 2 ORDER BY 3 DESC. Many idle in transaction sessions mean the app holds transactions open.
5. Say which connections fail, the error and the cause. Pooling comes before a larger compute.
