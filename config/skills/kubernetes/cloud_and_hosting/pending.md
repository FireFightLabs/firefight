---
name: kubernetes_pending
when: Kubernetes pods stay Pending, are never scheduled to a node, or a workload has fewer pods running than it asks for
tools: [resource_status, list_events, list_resources]
references: [debug/debug-pods.md, debug/debug-running-pod.md, scheduling/assign-pod-node.md, scheduling/taint-and-toleration.md, configuration/manage-resources-containers.md]
---
1. Call `resource_status`. A pod with phase Pending and no node has not been scheduled. Note the requests each container asks for.
2. Call `list_events`, `type` Warning, with `resource` set to the workload's name. The scheduler writes a FailedScheduling event that says why each node was ruled out.
3. Match the reason in its message:
   - Insufficient cpu or memory: no node has that much left unrequested. Scheduling counts requests, not what pods really use, so a large request blocks a pod on a cluster that looks idle. More nodes, smaller requests, or fewer other pods each solve it.
   - Untolerated taint: the pod lacks a toleration the free nodes require, such as nodes kept for one team or nodes being drained.
   - Did not match the node selector or affinity: the pod asks for node labels no ready node has.
   - A volume that cannot be bound or attached: a persistent volume claim without a volume, or a volume in another zone.
   - Too many pods on each node, or no nodes ready at all.
4. When no FailedScheduling event is left, events are kept an hour by default, so say the reason could not be read and what `resource_status` shows instead.
5. Fewer pods than desired with none Pending can also be a quota or a limit in the namespace refusing new pods. The workload's conditions and the Warning events say so.
