---
name: render_fixes
when: Writing or applying a fix that changes a service or database on Render, such as a restart, a rollback to an earlier deploy, setting how many instances run, deploying again, cancelling a deploy, or suspending or resuming a service or datastore
tools: [restart, rollback, scale, trigger_deploy, cancel_deploy, suspend_service, resume_service, recent_deploys, resource_status, run_history]
references: [debug/quick-workflows.md, debug/troubleshooting.md]
---
Each change is one step of a fix, made after the person confirms. While investigating, nothing is changed. Each step says how to undo it.

1. Read what is there first. `resource_status` gives the instances or autoscaling, the plan and what it runs, and `recent_deploys` what went live when. The undo comes from these values.
2. Pick the change:
   - Restart, for a web service, private service, background worker or Postgres database stuck in a bad state while its code is fine: `restart` with `resource`. Render replaces every instance with the same code and settings, without downtime for a service. It does not pick up environment changes made since the last deploy. Nothing to undo.
   - Roll back, when a deploy broke it: find the last deploy that was live and good in `recent_deploys`, then `rollback` with `resource` and `to` set to that deploy's id. Render puts that build back live without building again, as long as it still keeps the build. Rolling back this way leaves autodeploy on, so the next commit to the branch deploys again. Say so in the step, and that a person turns autodeploy off in Render if the rollback should hold. Undo by rolling back to the deploy that was live before.
   - Scale, for load a web service, private service or background worker cannot keep up with: `scale` with `resource` and `instances`. Render ignores it while autoscaling is on, and refuses then, so change the autoscaling range in Render instead. A free instance cannot scale. Undo by scaling back to the instances `resource_status` showed.
   - Deploy again, when a deploy failed for a reason that is gone, such as a flaky build or a stale build cache, or to put out a fixed commit: `trigger_deploy` with `resource`, and `clear_cache` true when the build cache is the suspect, `commit` for one commit, `image` for one tag of the image a service runs, or `deploy_only` true to deploy the last build that succeeded again without building. Autodeploy stays as it is. Follow it with `run_history` and its deploy id. Undo by rolling back to the deploy that was live before.
   - Cancel a deploy, when one still building or going live would make things worse: `cancel_deploy` with `resource` and `deploy`. The deploy that was live keeps serving. A cron job's deploys cannot be cancelled. Whoever started the deploy is asked first. Nothing to undo, `trigger_deploy` starts it again.
   - Suspend, to stop a service or datastore that does harm while it runs, such as a worker sending bad emails or a cron job writing bad data: `suspend_service` with `resource`. It stops running and serving until resumed, so say what stops with it. Undo with `resume_service`, which starts a service again on its last deploy.
3. A cron job cannot be restarted, and a Key Value instance cannot be restarted through Render's API. Say so rather than trying.
4. A change to environment variables, a plan, a disk or autoscaling is a step for a person in Render's dashboard. When the service is defined in a render.yaml Blueprint, the fix is a pull request to that file instead, since the next sync would undo a change made here.
