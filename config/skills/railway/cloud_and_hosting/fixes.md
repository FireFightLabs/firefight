---
name: railway_fixes
when: Writing or applying a fix to a service on Railway, such as a restart, a rollback to an earlier deployment, or a change in how many replicas it runs
tools: [rollback, restart, scale, recent_deploys, resource_status]
references: [deployments/deployment-actions.md, deployments/scaling.md, deployments/restart-policy.md]
---
Each change is one step of a fix, and each step says how to undo it. Read what is there first: `resource_status` gives the latest deployment, the replicas and the region, and `recent_deploys` what ran when. The undo comes from these values.

1. Restart, for a deployment that crashed and ran out of restarts while its code is fine: `restart` with the service in `resource`. Railway restarts the latest deployment's containers from the same image, without building. Nothing to undo.
2. Roll back, when a deployment broke it: find the last good deployment with `recent_deploys` and pass its id as `to` to `rollback`. Railway puts back that deployment's image and its variables without building, and only while it still keeps the image, which is for a few days after it stopped serving depending on the plan. A deployment it can no longer roll back to is redeployed from its commit in Railway instead, which builds it again. Undo by rolling back to the deployment that was live before.
3. Scale, for load the service cannot keep up with: `scale` with the replicas in `instances`, from 1 to 50 in total. Railway commits the new count for the service's region and starts the new replicas from the image it runs, without a redeploy. A service that runs in more than one region is scaled in Railway region by region. Undo by scaling back to the replicas `resource_status` showed.
4. A fix that changes the start command, the target port, a variable or the health check is a step for a person, naming the setting and the value. When the service is configured in code, such as a railway.json in its repository, the fix is a pull request to that file, since the next deployment reads it.
