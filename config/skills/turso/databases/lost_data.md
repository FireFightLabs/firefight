---
name: turso_lost_data
when: Finding what happened when a Turso database, or rows in it, went missing, and how it can be brought back
tools: [list_databases, get_database, list_branches, read_database, rollback, create_branch]
references: [features/point-in-time-recovery.md, features/recover-deleted-databases.md, features/branching.md]
---
1. Call `list_databases`. A database that is not there may have been deleted. On a paid plan Turso keeps a deleted database for five days, and a person can restore it from the Turso dashboard's Restore page.
2. When the database is there but rows are missing, run `read_database` with a count on the table, and on any column that records when rows changed, to find when they went.
3. Call `list_branches` for the database. A branch made before the loss still holds the rows.
4. To bring the rows back, call `rollback` on the database with `to` set to a moment just before the loss, as an ISO 8601 time such as 2026-10-20T14:30:00Z. Turso makes a new database from it as it was then, named like orders-restored-20261020143000, and leaves the database itself as it is. The moment has to be within the plan's window, which is 24 hours on the free plan and longer on paid ones. When `rollback` says the connected tool takes the moment some other way, call `create_branch` with the point in time it reports.
5. Check the rows in the restored database with `read_database`. The team then points the application at it by its own hostname, or copies the missing rows back, which is their call. A point in time restore through `rollback` cannot bring back a deleted database, which only the dashboard's Restore page in step 1 does.
6. Say what is missing, since when, what was restored and where, and what the team still needs to do.
