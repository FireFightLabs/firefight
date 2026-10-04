---
name: vercel_fixes
when: Writing or applying a fix for a Vercel project, such as rolling production back to an earlier deployment or promoting a deployment to production
tools: [rollback, promote_deployment, recent_deploys, resource_status]
---
Vercel changes production by moving its domains between deployments that are already built, so a rollback or a promotion takes effect in seconds and builds nothing. Each step of a fix says how to undo it.

1. Read what is there first. `recent_deploys` shows which deployment serves production now and the earlier ones, and `resource_status` shows the last rollback or promotion. The undo comes from these.
2. Pick the change:
   - Roll back, when a production deployment broke the site: `rollback` with `to` set to the last production deployment that was ready before it. On the Hobby plan only the previous production deployment can be chosen. After a rollback Vercel stops moving the production domains to new deployments on their own, so a fix that is merged later does not go live by itself. Undo by promoting the deployment that was serving before.
   - Promote, to put a ready production deployment on the production domains, such as the fixed one after a rollback: `promote_deployment` with the project and the deployment. It also turns automatic assignment of the production domains back on. A preview deployment cannot be promoted this way, since Vercel builds it again for production. Undo by promoting, or rolling back to, the deployment that served before.
3. A rollback does not change environment variables or the project's settings, and cron jobs go back to the ones the earlier deployment defined. When the cause is a setting or a variable, the fix is a step for a person in Vercel.
4. When the project is defined as code, such as a vercel.json in the repository, a change to its settings is a pull request to that code, since the next deployment would undo a change made by hand.
