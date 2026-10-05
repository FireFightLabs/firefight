---
name: google_cloud_fixes
when: Writing or applying a fix that changes anything on Google Cloud, such as rolling a Cloud Run service back, keeping more of its instances warm, or restarting a Cloud SQL or Compute Engine instance
tools: [rollback, scale, restart, recent_deploys, resource_status]
references: [run/rollouts-rollbacks-traffic-migration.md, run/min-instances.md, run/max-instances.md, sql/postgres-start-stop-restart.md, compute/reset-instance.md]
---
Each change is one step of a fix and says how to undo it. Read the current values first with `resource_status` and `recent_deploys`, since the undo comes from them.

1. Roll back a Cloud Run service: `rollback` with `to` set to the revision that should serve, by its name in `recent_deploys`. All traffic moves to it and no new revision is made. Undo by moving the traffic back to the revision that served before, which `recent_deploys` showed with its share.
2. Keep more Cloud Run instances warm: `scale` with `instances` set to the fewest to keep running. It is set on the service, so no new revision is made, and warm instances are billed while they run. Undo by setting the fewest back to what `resource_status` showed. A service set to manual scaling refuses this, and its count is changed in the console.
3. Restart a Cloud SQL instance or reset a Compute Engine instance: `restart`. A Cloud SQL restart drops connections for a few minutes. A reset loses what was in the instance's memory. Neither can be undone, so say so in the step.
4. When the service is defined as code, such as Terraform, or deployed from a pipeline that sets traffic, the fix is a change to that code too, since the next apply or deploy would undo a change made here.
5. A refusal that says the service account lacks a permission is the workspace's to fix in Google Cloud's IAM, such as Cloud Run Developer for a rollback or scaling. Say so in the step, and keep the rest of the fix.
