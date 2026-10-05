---
name: google_cloud_gke
when: A GKE cluster or the workloads in it have a problem, such as pods restarting, nodes not ready, or a cluster in an error state
tools: [resource_status, search_logs]
references: [gke/troubleshooting.md, gke/crashloopbackoff.md, logging/logging-query-language.md]
---
1. Call `resource_status` on the cluster for its state, control plane version and node pools, each with its state, machine type and size. A pool running with errors or a cluster that is degraded or reconciling, such as during an upgrade, explains a lot.
2. Read the cluster's logs with `search_logs`, which covers its containers, pods and nodes. Use `text` with the workload's or pod's name to narrow to one, and look for CrashLoopBackOff, OOMKilled, ImagePullBackOff, failed scheduling and evictions.
3. Firefight reaches the cluster through Google Cloud's API, not Kubernetes, so it cannot list, restart or scale workloads. Say what to run with kubectl as a step for a person, such as describing the pod, reading its previous container's logs, or rolling the deployment back.
4. Say what is wrong, the evidence from the logs, and the fix.
