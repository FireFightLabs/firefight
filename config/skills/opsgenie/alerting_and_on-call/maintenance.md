---
name: opsgenie_maintenance
when: Quieting Opsgenie for planned work, such as a migration or a release window, so the alerts it expects do not page anyone
tools: [list_maintenance_targets, create_maintenance]
---
1. Call `list_maintenance_targets` for the integrations and alert policies by name and id. An integration's alerts stop while it is in maintenance, and a policy stops acting.
2. Pick only what the work touches, such as the monitoring integration of the service being migrated. Quieting everything hides a real problem behind the planned one.
3. Choose how long: a fixed length, or schedule with a start and an end around the work.
4. Tell the person what will be quiet and until when, then call `create_maintenance` with a `description` naming the work. The person confirms the call.
5. Say when it ends, and that anything the integration raises in that time will not page anyone.
