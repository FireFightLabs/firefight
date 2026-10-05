---
name: neon_changes
when: Finding what changed on a Neon project before something broke, or undoing a change to its data or computes
tools: [recent_deploys, list_branches, compare_database_schema, list_snapshots, restart]
---
1. Call `recent_deploys` for the project, then for the branch. Operations name what Neon did and when: computes started, suspended or reconfigured, branches created, reset or restored.
2. Call `list_branches` for when each branch was created and last changed. A branch reset from its parent, or restored, holds different data than the app expects.
3. Call `compare_database_schema` with `project_id`, `branch_id` and `database_name` to see how the branch's schema differs from its parent. A schema change applied to the default branch is the usual cause of new errors.
4. Call `list_snapshots` when the data itself has to go back. Restoring a snapshot with restore_snapshot, or resetting a branch from its parent replaces data on the branch and cannot be undone, so it is always a step for the person.
5. A compute stuck in a bad state while its configuration is fine can be restarted with `restart`, which drops open connections. Say so before asking for it.
