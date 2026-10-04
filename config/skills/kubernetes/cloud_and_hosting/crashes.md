---
name: kubernetes_crashes
when: Finding why a Kubernetes workload's pods keep restarting, crash on start, are killed for memory, are evicted, or fail their probes
tools: [resource_status, workload_logs, search_logs, list_events, query_metrics, recent_deploys]
references: [workloads/pod-lifecycle.md, debug/determine-reason-pod-failure.md, configuration/probes.md, configuration/manage-resources-containers.md, scheduling/node-pressure-eviction.md]
---
1. Call `resource_status`. For each pod, note the restarts, the reason its container is waiting, and why it last stopped with its exit code and time.
2. Read the last lines the crashed container printed with `workload_logs` and `previous` true. Those are the container before its last restart, which is where the reason usually is. The current container may only have started again. Use `pod` to read one pod.
3. Match the cause:
   - CrashLoopBackOff: the container keeps exiting and the kubelet waits longer before each restart, 10 seconds doubling up to five minutes, and resets after ten minutes running. It names the loop, not the cause, so read the previous logs and the exit code.
   - OOMKilled, exit code 137: the container used more memory than its limit and was killed. Compare the limit `resource_status` shows with `query_metrics` for memory on the pods still running. A limit far below what the app needs, or memory that grows until the kill, are the two usual stories.
   - Error with another exit code: the process itself exited, such as a missing setting, a failed connection at boot or an unhandled error. The previous logs say which.
   - A failed liveness probe restarts the container, a failed readiness probe only takes the pod out of its Service, and a startup probe holds the other two back until it passes. A probe whose delay and threshold are shorter than the app's boot time fails on every start, and the events name the probe that failed.
   - Evicted: the node ran short of memory, disk or ephemeral storage and removed pods to recover. Call `list_events` for the eviction and what the node lacked.
4. Call `list_events`, `type` Warning, with `resource` set to the workload's name, for BackOff, Unhealthy, Killing and Evicted events and their counts.
5. Call `recent_deploys`. Restarts that began with a new revision point at that change, such as a new image, a new setting or a lower limit.
