---
name: neon_triage
when: Starting on anything wrong with a Neon Postgres database, before knowing what kind of problem it is
tools: [list_projects, resource_status, recent_deploys, list_branches, search_logs]
references: [neon/logs-loki.md]
---
On the resource map, a Neon project is a database, each of its branches is a branch of it, and each compute serving a branch is a compute. `resource_status`, `recent_deploys`, `search_logs` and `restart` take any of them by name. Neon's own tools take a project id and a branch id that starts with br-, never a branch's name, and `list_branches` turns a name into its id.

1. When the person did not name the project, find it with `list_projects`. Production is the project's default branch.
2. Call `resource_status` for the branch the app uses. It names each compute serving it, its state, which is active, idle when suspended or init while starting, its autoscaling range in compute units and when it suspends. An idle compute wakes on the first connection, which adds a short delay. A disabled one refuses every connection until a person enables it.
3. Call `recent_deploys` for the branch. Neon keeps no deploys, so this lists the operations it ran: starting and suspending computes, applying configuration, creating or restoring branches. A failed operation, or a restore or configuration change just before the problem, is the first suspect.
4. Then load the skill that fits what was reported: neon_connections when the app cannot connect, neon_slow_queries when it is slow, neon_locks when queries hang.
5. `search_logs` reads what Neon Functions and Object Storage on a branch print. Postgres does not write to it yet, so read the database through the other skills.
