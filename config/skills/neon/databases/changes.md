---
name: neon_changes
when: Finding what changed on a Neon project before something broke, or undoing a change to its data or computes
tools: [recent_deploys, run_history, list_branches, compare_database_schema, list_snapshots, rollback, restart]
---
1. Call `recent_deploys` for the project, then for the branch. Operations name what Neon did and when: computes started, suspended or reconfigured, branches created, reset or restored. `run_history` with `run` reads one operation by its id, however old.
2. Call `list_branches` for when each branch was created and last changed. A branch reset from its parent, or restored, holds different data than the app expects.
3. Call `compare_database_schema` with `project_id`, `branch_id` and `database_name` to see how the branch's schema differs from its parent. A schema change applied to the default branch is the usual cause of new errors.
4. Call `list_snapshots` when the data itself has to go back. `rollback` on the branch with `to` a snapshot's id restores that snapshot onto it and moves its computes there, and with `to` parent resets it to its parent's current state. Both replace the branch's data and cannot be undone, and open connections drop, so say what will be lost before asking for it. Neon's server has no point in time restore, so a moment with no snapshot is a step for the person in Neon's console.
5. A compute stuck in a bad state while its configuration is fine can be restarted with `restart`, which drops open connections. Say so before asking for it.
