---
name: kubernetes_fixes
when: Writing or applying a fix to a Kubernetes workload, such as going back to an earlier revision, restarting its pods, or changing how many it runs
tools: [rollback, restart, scale, rollout_pause, rollout_resume, run_cronjob_now, suspend_cronjob, resume_cronjob, resource_status, recent_deploys, run_history]
references: [workloads/deployment.md, workloads/rollback-daemon-set.md, workloads/scale-stateful-set.md, workloads/horizontal-pod-autoscale.md, access/rbac.md]
---
Each change is one step of a fix, and each says how to undo it. While investigating, nothing is changed.

1. Read what is there first. `resource_status` gives the replicas and what each container runs, and `recent_deploys` the revisions with the current one marked. The undo comes from these values.
2. Pick the change:
   - Go back to an earlier revision, when a new one broke it: `rollback` with `to` set to the revision number from `recent_deploys`. It works for deployments, statefulsets and daemonsets, as kubectl rollout undo does, and the pods roll out again as the workload's strategy says. It restores the pod template only. Undo it by going back to the revision that was current before, which comes back under a new number.
   - Restart, for pods stuck in a bad state while the code is fine: `restart`. Every pod is replaced as the strategy says, so a deployment keeps serving while it happens. Nothing to undo.
   - Scale, for load the pods cannot keep up with, or to stop a workload doing harm: `scale` with `instances`. Only deployments and statefulsets scale. A statefulset adds and removes pods one at a time, in order, unless its pod management policy is Parallel. Undo by scaling back to the replicas `resource_status` showed.
   - Pause a deployment's rollout, to stop a bad rollout spreading while the fix is decided: `rollout_pause`. Pods already running keep running and nothing new rolls out. Undo with `rollout_resume`.
   - Suspend a cronjob whose runs do harm: `suspend_cronjob`. Jobs already running carry on. Undo with `resume_cronjob`, and say that runs missed while suspended start at once unless it has a starting deadline.
   - Run a cronjob now, such as a cleanup or a sync that failed on its schedule: `run_cronjob_now`. Nothing to undo, so say what the job does before it runs, and follow it with `run_history`.
3. A horizontal pod autoscaler that targets the workload sets its replicas itself, between its own minimum and maximum, so a scale outside those bounds is moved back. The answer names the autoscaler when there is one. Changing it is a step for a person.
4. A paused deployment cannot be rolled back or restarted. Resuming it with `rollout_resume` also rolls out whatever was changed while paused, so read what changed first and say so in the step.
5. When the workload is defined as code, such as manifests, a Helm chart or Kustomize in a repository, or kept in step by a GitOps tool, the fix is a pull request to that code too, since the next apply or sync would undo a change made here.
6. A refusal that says the service account's role cannot make the change is the team's to fix in the cluster. It names the permission, such as patch on deployments or on deployments/scale, or create on jobs. Say so in the step, and keep the rest of the fix.
