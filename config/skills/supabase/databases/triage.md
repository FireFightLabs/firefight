---
name: supabase_triage
when: Starting on anything wrong with a Supabase project's database, before knowing what kind of problem it is
tools: [list_projects, resource_status, recent_deploys, search_logs, get_advisors]
references: [postgres/monitor-pg-stat-statements.md]
---
On the resource map, a Supabase project is a database, and each of its branches is a project of its own. `resource_status`, `recent_deploys` and `search_logs` take either by name. Supabase's own tools take the project's ref as `project_id`.

1. When the person did not name the project, find it with `list_projects`.
2. Call `resource_status` for it. ACTIVE_HEALTHY is up. INACTIVE means the project is paused and answers nothing until it is restored, COMING_UP and RESTORING mean it is starting, and ACTIVE_UNHEALTHY means one of its services is failing.
3. Call `recent_deploys` for the migrations applied, newest first. A migration applied just before the problem is the first suspect.
4. Call `search_logs` around the problem for what Postgres said, and with `stream` requests for the API requests reaching the project and their status codes.
5. Call `get_advisors` with `type` performance, and security when data may be exposed. Each finding links to how to fix it, and the person should get those links.
6. Then load the skill that fits: supabase_connections when the app cannot connect, supabase_slow_queries when it is slow, supabase_migrations when a schema change or a branch went wrong.
