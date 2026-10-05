---
name: convex_changes
when: Finding what changed on Convex before something broke, such as a push of new functions or schema, or an index build
tools: [recent_pushes, recent_deploys, search_errors, resource_status]
references: [insights/SKILL.md]
---
1. Call `recent_deploys` for the deployment, or `recent_pushes` with `days` to look further back. Each push says when it happened and who made it: a person in the dashboard, or a deploy key or token, which is usually a build pipeline. An index build shows up as its own event.
2. Call `search_errors` for the hours around the push. Errors that start right after it point at the new code or schema. Errors that were there before it did not come from it.
3. Call `resource_status` to rule out a pause or a usage limit stop at the same time.
4. Convex has no rollback. Undoing a bad push means pushing the earlier code again from the team's repository or pipeline, so say which push came right before the trouble and suggest that, and never claim Firefight can do it.
