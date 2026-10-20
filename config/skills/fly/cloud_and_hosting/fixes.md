---
name: fly_fixes
when: Writing or applying a fix to an app on Fly.io, such as a restart, a rollback to an earlier release, starting or stopping its machines, or taking one machine out of traffic
tools: [rollback, restart, start_app, stop_app, suspend_app, cordon_machine, uncordon_machine, recent_deploys, resource_status]
references: [deploy/rollback-guide.md, machines/machine-states.md]
---
A change goes through as one step of a fix, and each step says how to undo it.

1. Read what is there first. `resource_status` gives each machine's state and image, and `recent_deploys` each release's version, status and image. The undo comes from these values.
2. Pick the change:
   - Restart, for an app stuck in a bad state while its code is fine: `restart` on the app. Every running machine reboots on the image it already runs, one at a time, and stopped machines are left as they are. Nothing to undo.
   - Start, for an app that is down because its machines stopped or were suspended: `start_app` on the app, or on one `machine`. Each starts on the image it already runs, one at a time, and a suspended one resumes where it was when Fly can. Undo with `stop_app` on the machines it started.
   - Stop or suspend, for machines that should not run for now, such as a worker flooding a database: `stop_app` or `suspend_app` on the app, or on one `machine`. A stopped machine serves nothing, and one Fly's proxy starts on demand starts again on the next request. Undo with `start_app`.
   - Cordon, for one machine that answers badly while the others are fine: `cordon_machine` with that `machine`. It keeps running, so its logs and state can still be read, while Fly's proxy sends it no requests. Undo with `uncordon_machine`. Never cordon every machine of an app, since nothing would serve it.
   - Roll back, when a release broke it: find the last release that worked with `recent_deploys`, then `rollback` with `to` set to its version, such as v41. Machines move to that release's image one at a time, each started again before the next. A machine that changed since it was read, such as during a deploy, or that does not start again, stops the rollback there, and the machines after it are left as they were and named, so check that machine before running it again. Undo by rolling back to the release that was serving before, the newest one `recent_deploys` showed. The app's settings, secrets and fly.toml do not go back, so a release that broke because of a setting needs that setting changed by a person instead. Fly's own release list does not show a rollback made this way, and the next deploy replaces it.
3. Fly has no single call that sets how many machines an app runs, so adding or removing machines, giving them more memory or a larger size, and changing secrets are steps for a person in Fly.io. Name the app, the machines and the value to set.
4. When the app is defined as code, such as fly.toml in a repository deployed by a pipeline, the lasting fix is a pull request to that code, since the next deploy would undo a change made here.
5. A refusal saying the token cannot make the change means it is a read-only token. Say so in the step, and keep the rest of the fix.
