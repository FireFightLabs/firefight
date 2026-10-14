---
name: statuspage_maintenance
when: Announcing planned work on an Atlassian Statuspage page, such as a migration or an upgrade, and keeping customers told while it runs
tools: [list_components, list_incidents, schedule_maintenance, update_maintenance, post_incident_update, get_incident]
---
1. Call `list_components` and pick only what the work touches. Call `list_incidents` with `list` upcoming to see whether it is already announced.
2. Agree the title, the message and the window with the person. Customers read it ahead of time.
3. Call `schedule_maintenance` with `scheduled_for` and `scheduled_until` around the work. `auto_start` and `auto_complete` move it on time, `components_under_maintenance` shows the components under maintenance while it runs, and `remind_before` reminds subscribers. Ask the person whether subscribers are told, for `deliver_notifications`.
4. `update_maintenance` moves the window when the work moves.
5. While it runs, `post_incident_update` tells customers how it is going at `status` in_progress, verifying or completed.
6. Read it back with `get_incident` and give the person its link.
