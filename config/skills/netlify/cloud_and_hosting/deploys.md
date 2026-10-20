---
name: netlify_deploys
when: A Netlify deploy failed, is stuck or waits for approval, or a deploy that went live broke the site, and it may need rolling back to an earlier deploy, locking there, canceling or building again
tools: [recent_deploys, describe_deploy, resource_status, rollback, lock_deploy, unlock_deploy, cancel_deploy, trigger_build, run_history]
references: [deploy/deployment-patterns.md, deploy/netlify-toml.md, config/SKILL.md]
---
Netlify keeps every deploy as it was built, so putting an earlier one back is instant and builds nothing.

1. Call `recent_deploys` for the site, with `limit` large enough to reach the last deploy that worked. Each line gives when it was made and published, its state, its context (production, deploy-preview or branch-deploy), branch, commit and title, the error Netlify gave when it failed, and which one is live.
2. A deploy in state error, or one that never finished, did not go live. Call `describe_deploy` with its `site` and `deploy` for the error Netlify gave. A failed build is a fix in the code or the build settings, never a rollback, since what was live before is still live.
3. When a production deploy that went live is the suspect, line its published time up against when the trouble began. A deploy published after the trouble began did not cause it.
4. To roll back, pick the last production deploy before the suspect that is in state ready, and call `rollback` with the site as `resource` and that deploy's id as `to`. Only a ready deploy can be published. Undo it by rolling back to the deploy that was live before, which the answer names.
5. While auto publishing is on, the next production deploy from Git publishes over the rollback. Lock it with `lock_deploy` on the site, which keeps the deploy that is live now, as its own step after the rollback, and say in the fix that `unlock_deploy` turns auto publishing back on once the fix has shipped. Undo a lock with `unlock_deploy`.
6. A deploy that is still building but should never go live, such as one from the wrong branch, is stopped with `cancel_deploy` and its id. Only one that has not ended can be canceled. A build that failed for a passing reason, or one canceled by mistake, is built again with `trigger_build`, with `branch` for a branch deploy and `clear_cache` when a stale cache is the suspect. Follow the new deploy with `run_history` and the id the answer gives.
7. A deploy in state pending_review comes from someone the site does not trust, such as a pull request from outside the team, and waits for a team member to approve it in Netlify before it builds. Say who has to approve it, since Firefight cannot.
8. Say which deploy came right before the trouble, what it changed (its branch, commit and title), and how sure the timing makes you.
