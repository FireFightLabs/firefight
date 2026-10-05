---
name: turso_lost_data
when: Finding what happened when a Turso database, or rows in it, went missing, and how it can be brought back
tools: [list_databases, get_database, list_branches, read_database]
references: [features/point-in-time-recovery.md, features/recover-deleted-databases.md, features/branching.md]
---
1. Call `list_databases`. A database that is not there may have been deleted. On a paid plan Turso keeps a deleted database for five days, and a person can restore it from the Turso dashboard's Restore page.
2. When the database is there but rows are missing, run `read_database` with a count on the table, and on any column that records when rows changed, to find when they went.
3. Call `list_branches` for the database. A branch made before the loss still holds the rows.
4. Point in time recovery creates a new database from this one as it was at a chosen moment, within the plan's window, which is 24 hours on the free plan and longer on paid ones. The team then points the application at the new database. It cannot bring back a deleted database.
5. Say what is missing, since when, and which way back fits. Every one of them is a change for a person to make.
