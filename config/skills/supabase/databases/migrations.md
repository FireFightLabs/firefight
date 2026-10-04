---
name: supabase_migrations
when: Finding what changed in a Supabase project's schema before something broke, or why a branch's migrations failed
tools: [recent_deploys, list_branches, search_logs, list_tables]
---
1. Call `recent_deploys` for the project. Each migration is named by its version, which is the time it was written, and its name. The newest ones are what changed last.
2. Call `list_branches`. A branch whose status is MIGRATIONS_FAILED or FUNCTIONS_FAILED did not finish setting up, and the error is in its logs.
3. Call `search_logs` for the branch, or the project, around when the migration ran, with `text` ERROR, for what Postgres refused.
4. Call `list_tables` to compare the schema with what the app expects, such as a column the app reads that a migration renamed or dropped.
5. Say which migration changed what and when. Supabase does not undo a migration, so going back is a new migration the person writes and applies.
