---
name: supabase_migrations
when: Finding what changed in a Supabase project's schema before something broke, or why a branch's migrations failed
tools: [recent_deploys, list_branches, run_history, get_action_run_logs, search_logs, list_tables, rollback]
---
1. Call `recent_deploys` for the project. Each migration is named by its version, which is the time it was written, and its name. The newest ones are what changed last.
2. Call `list_branches`. A branch whose status is MIGRATIONS_FAILED or FUNCTIONS_FAILED did not finish setting up, and the error is in its logs.
3. Call `run_history` for the branch for its action runs, the runs that clone, migrate, seed and deploy it, with how each ended and how long they usually take. With `run` set to a run's id it reads its steps, and `get_action_run_logs` with `project_id` and `run_id` reads what that run printed, which says why a migration failed.
4. Call `search_logs` for the branch, or the project, around when the migration ran, with `text` ERROR, for what Postgres refused.
5. Call `list_tables` to compare the schema with what the app expects, such as a column the app reads that a migration renamed or dropped.
6. Say which migration changed what and when. On the production branch Supabase does not undo a migration, so going back is a new migration the person writes and applies, or a restore of the whole database to a moment, which the supabase_recovery skill covers.
7. A preview branch can go back: `rollback` on the branch with `to` the version of the last good migration, from `recent_deploys`, resets it to that migration. Changes to its data or schema that no migration made are lost, so say so before asking for it, and read `list_branches` for when its status says it is done.
