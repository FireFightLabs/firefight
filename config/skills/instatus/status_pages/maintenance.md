---
name: instatus_maintenance
when: Announcing planned work on an Instatus page, such as a migration or an upgrade, and keeping customers told while it runs
tools: [list_components, list_maintenances, schedule_maintenance, update_maintenance, post_maintenance_update, get_maintenance]
---
1. Call `list_components` and pick only what the work touches. Call `list_maintenances` to see whether it is already announced.
2. Agree the title, the message and the window with the person. Customers read it ahead of time.
3. Call `schedule_maintenance` with `start` and `end` around the work. Its `components` show under maintenance. `auto_start` and `auto_end` move it on time, and `remind_minutes_before` reminds subscribers. Ask the person whether subscribers are told, for `notify`.
4. `update_maintenance` moves the window when the work moves.
5. While it runs, `post_maintenance_update` tells customers how it is going at `status` INPROGRESS or COMPLETED.
6. Read it back with `get_maintenance` and give the person its link.
