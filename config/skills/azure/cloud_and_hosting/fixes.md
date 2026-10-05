---
name: azure_fixes
when: Writing or applying a fix that changes anything on Azure, such as swapping a slot, sending a Container App's traffic to an earlier revision, restarting, or scaling
tools: [rollback, restart, scale, recent_deploys, resource_status]
references: [app-service/deploy-staging-slots.md, app-service/manage-scale-up.md, container-apps/traffic-splitting.md, container-apps/scale-app.md, container-apps/revisions-manage.md]
---
Each change is one step of a fix and says how to undo it. Read the current values first with `resource_status` and `recent_deploys`, since the undo comes from them.

1. Roll back an App Service or Function app: `rollback` with `to` set to the deployment slot to swap with production. What the slot runs goes live and production moves into the slot. Undo by swapping the same slot again.
2. Roll back a Container App: `rollback` with `to` set to the revision that should take all the traffic. It needs multiple revision mode, and an inactive revision is activated first. Undo by sending the traffic back to the revisions that took it before.
3. Restart: `restart` restarts an App Service or Function app, every active revision of a Container App, or a PostgreSQL flexible server. There is nothing to undo. Azure SQL has no restart.
4. Scale: `scale` with `instances`. For an App Service app this sets its App Service plan's instance count, which every app on the plan shares, so name them. A plan that scales on its own, such as Consumption, refuses it. For a Container App it sets the fewest replicas, which makes a new revision. Undo by setting the count `resource_status` showed.
5. When the app is defined as code, such as Bicep or Terraform, or deployed from a pipeline, the fix is a change to that code too, since the next deploy would undo a change made here.
6. A refusal that says the service principal lacks a permission is the workspace's to fix in Azure's access control, such as Website Contributor for an App Service app. Say so in the step, and keep the rest of the fix.
