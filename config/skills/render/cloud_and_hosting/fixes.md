---
name: render_fixes
when: Writing or applying a fix that changes a service or database on Render, such as a restart, a rollback to an earlier deploy or setting how many instances run
tools: [restart, rollback, scale, recent_deploys, resource_status]
references: [debug/quick-workflows.md, debug/troubleshooting.md]
---
Each change is one step of a fix, made after the person confirms. While investigating, nothing is changed. Each step says how to undo it.

1. Read what is there first. `resource_status` gives the instances or autoscaling, the plan and what it runs, and `recent_deploys` what went live when. The undo comes from these values.
2. Pick the change:
   - Restart, for a web service, private service, background worker or Postgres database stuck in a bad state while its code is fine: `restart` with `resource`. Render replaces every instance with the same code and settings, without downtime for a service. It does not pick up environment changes made since the last deploy. Nothing to undo.
   - Roll back, when a deploy broke it: find the last deploy that was live and good in `recent_deploys`, then `rollback` with `resource` and `to` set to that deploy's id. Render puts that build back live without building again, as long as it still keeps the build. Rolling back this way leaves autodeploy on, so the next commit to the branch deploys again. Say so in the step, and that a person turns autodeploy off in Render if the rollback should hold. Undo by rolling back to the deploy that was live before.
   - Scale, for load a web service, private service or background worker cannot keep up with: `scale` with `resource` and `instances`. Render ignores it while autoscaling is on, and refuses then, so change the autoscaling range in Render instead. A free instance cannot scale. Undo by scaling back to the instances `resource_status` showed.
3. A cron job cannot be restarted, and a Key Value instance cannot be restarted through Render's API. Say so rather than trying.
4. A change to environment variables, a plan, a disk or autoscaling is a step for a person in Render's dashboard. When the service is defined in a render.yaml Blueprint, the fix is a pull request to that file instead, since the next sync would undo a change made here.
