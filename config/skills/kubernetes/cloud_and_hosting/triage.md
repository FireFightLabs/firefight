---
name: kubernetes_triage
when: Starting on anything wrong with a workload in a Kubernetes cluster, before knowing what kind of problem it is
tools: [list_resources, resource_status, list_events, recent_deploys, query_metrics, search_logs]
references: [debug/debug-pods.md, debug/debug-running-pod.md, workloads/pod-lifecycle.md]
---
Work from the outside in, and stop as soon as one of these explains what was reported.

1. Call `list_resources`, with `namespace` when the connection reaches several, for the workload's kind and name and how many of its pods are ready. A service or ingress in front of it is listed too, with the selector or hosts it routes by.
2. Call `resource_status` on the workload. Read the desired, ready, up to date and available replicas, the conditions, and for each pod its phase, restarts and why its containers last stopped.
3. Match what it shows:
   - A pod waiting in CrashLoopBackOff, restarts climbing, or a container last stopped as OOMKilled or Error: load the kubernetes_crashes skill.
   - A pod Pending, or no node named for it: load the kubernetes_pending skill.
   - Pods waiting in ErrImagePull or ImagePullBackOff, a Progressing condition with ProgressDeadlineExceeded, or old and new pods side by side: load the kubernetes_rollouts skill.
   - Every pod running and ready, but requests failing or not arriving: load the kubernetes_traffic skill.
   - A cronjob or job: load the kubernetes_jobs skill.
4. Call `list_events` for the namespace, `type` Warning. Events say what the cluster did and refused, such as a failed probe, a scheduling failure or an eviction. The API server keeps them for an hour by default, so an older incident may have none left.
5. Call `recent_deploys`. A revision made shortly before the trouble began is the first suspect.
6. Call `query_metrics` for cpu and memory. It is the current reading only, so compare it with the requests and limits it prints, not with a past level.
7. Read what the pods printed with `search_logs` around the moment it started.
