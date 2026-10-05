---
name: netlify_deploys
when: A Netlify deploy failed, or a deploy that went live broke the site, and it may need rolling back to an earlier deploy
tools: [recent_deploys, describe_deploy, resource_status, rollback]
references: [deploy/deployment-patterns.md, deploy/netlify-toml.md, config/SKILL.md]
---
Netlify keeps every deploy as it was built, so putting an earlier one back is instant and builds nothing.

1. Call `recent_deploys` for the site, with `limit` large enough to reach the last deploy that worked. Each line gives when it was made and published, its state, its context (production, deploy-preview or branch-deploy), branch, commit and title, the error Netlify gave when it failed, and which one is live.
2. A deploy in state error, or one that never finished, did not go live. Call `describe_deploy` with its `site` and `deploy` for the error Netlify gave. A failed build is a fix in the code or the build settings, never a rollback, since what was live before is still live.
3. When a production deploy that went live is the suspect, line its published time up against when the trouble began. A deploy published after the trouble began did not cause it.
4. To roll back, pick the last production deploy before the suspect that is in state ready, and call `rollback` with the site as `resource` and that deploy's id as `to`. Only a ready deploy can be published. Undo it by rolling back to the deploy that was live before, which the answer names.
5. While auto publishing is on, the next production deploy from Git publishes over the rollback. Tell the person to lock auto publishing on the site's Deploys page in Netlify until the fix has shipped, and to unlock it afterwards.
6. Say which deploy came right before the trouble, what it changed (its branch, commit and title), and how sure the timing makes you.
