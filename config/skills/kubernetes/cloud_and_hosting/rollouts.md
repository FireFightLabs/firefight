---
name: kubernetes_rollouts
when: A Kubernetes deployment, statefulset or daemonset that is stuck rolling out, failed to roll out, cannot pull its image, or changed just before something broke
tools: [resource_status, run_history, recent_deploys, list_events, workload_logs, search_logs, rollout_pause, rollout_resume]
references: [workloads/deployment.md, workloads/statefulset.md, workloads/daemonset.md, configuration/images.md]
---
1. Call `resource_status`. Compare desired, ready, up to date and available replicas, and read the conditions. A deployment whose Progressing condition says ProgressDeadlineExceeded has not finished rolling out within its progress deadline, 600 seconds unless set. The controller keeps trying, but the rollout has stalled.
2. Call `run_history` for its rollouts, one per revision, newest first. The current one says whether it is still going, failed at its progress deadline or finished, and how long finished ones usually take. With `run` set to a revision number it lists each pod of that revision, how it stands, why a container stopped and how to read that pod's log, so the first pod that failed is the place to start. Kubernetes keeps no end time for an earlier rollout, and a revision rolled back is marked cancelled.
3. Call `recent_deploys` for the revisions, newest first, with the images each ran and the change cause when one was recorded. A new revision appears only when the pod template changed, so scaling alone never makes one.
4. Read why the new pods do not become ready:
   - ErrImagePull or ImagePullBackOff: Kubernetes could not pull the image, such as a tag that does not exist, a private registry without credentials, or a registry that refused or rate limited it. The waiting message and `list_events` with `type` Warning name the image and the error.
   - The new pods crash or fail readiness: load the kubernetes_crashes skill, since a rollout waits for new pods to be ready before it replaces old ones.
   - The new pods are Pending: load the kubernetes_pending skill, often the extra pods a rolling update adds for a while.
   - Paused: a paused deployment rolls nothing out until `rollout_resume`, and it cannot be rolled back or restarted while paused.
5. Compare what the new revision changed with the one before, from the images in `recent_deploys`, and read the new pods' first lines with `workload_logs`.
6. When the new revision is what broke it, the fix is usually going back to the last revision that worked. Load the kubernetes_fixes skill. To stop a bad rollout from going further while that is decided, `rollout_pause` halts it where it stands. Going back restores the pod template only, so a change to a ConfigMap, a Secret or the replica count is not undone by it.
