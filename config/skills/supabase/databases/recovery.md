---
name: supabase_recovery
when: A Supabase project is stuck or unhealthy and may need a restart, or its data was damaged and may need restoring to an earlier moment
tools: [resource_status, list_backups, restart, rollback]
---
1. Call `resource_status` for the project. Which service is unhealthy says what a restart would touch, and a project still COMING_UP or RESTORING needs time rather than a restart.
2. When a service stays unhealthy and the person agrees, call `restart`. The project is unreachable for a short while and open connections drop, so say that before asking. Call `resource_status` again after for when it is back.
3. When data was damaged, call `list_backups` for whether point in time recovery is on and the earliest and latest moments it can restore to.
4. Only when the person agrees, call `rollback` for the project with `to` set to a moment just before the damage, as an ISO 8601 time. Every change after that moment is lost and the project is unavailable while it restores, so name the moment and what is lost before asking. A preview branch goes back to a migration instead, as the supabase_migrations skill says.
5. Neither is offered on a connection made read only, so say the connection would need read and write for it.
