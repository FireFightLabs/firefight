---
name: kubernetes_api
when: A question about the cluster that the other Kubernetes tools do not answer, such as config maps, persistent volume claims, network policies, horizontal pod autoscalers, pod disruption budgets, nodes, resource quotas, custom resources or one object in full, and finding out whether the API offers a read at all
tools: [api_read, list_resources, workload_logs]
references: [api/index.md]
---
`api_read` sends a GET to any path of the cluster's API server, as kubectl get --raw does, and answers what it said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollout and scale tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped: `list_resources` for the workloads, `workload_logs` for logs. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read by API group, then the group's page it names for the parameters and the fields each read answers. A custom resource is under /apis/<group>/<version>, and GET /apis lists the groups this cluster serves.
3. Name the namespace in the path, such as /api/v1/namespaces/<namespace>/configmaps. A list across the cluster that holds objects of a namespace this connection does not reach is refused.
4. A list answers one page. Pass limit in `query`, and to read on, continue set to the answer's metadata.continue. Filter with labelSelector or fieldSelector rather than reading everything.
5. Secrets come back as their names, with their data hidden, and a proxy, exec, attach or port forward is never sent. When the API server answers that the service account cannot read something, say which get or list to add to its role.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /api/v1/namespaces/{namespace}/pods (labelSelector, fieldSelector, limit): A namespace's pods, with each one's phase, restarts, node and container states.
- GET /api/v1/pods (labelSelector, fieldSelector, limit): Pods across every namespace, filtered by label or field such as a node or phase.
- GET /api/v1/namespaces/{namespace}/pods/{name}: One pod, with its containers, last exit reasons, restarts, conditions and node.
- GET /api/v1/namespaces/{namespace}/pods/{name}/log (container, previous, tailLines, sinceSeconds, timestamps): One container's logs, or its previous run's after a crash.
- GET /api/v1/namespaces/{namespace}/events (labelSelector, fieldSelector, limit): A namespace's events, such as failed scheduling, image pulls, kills and probe failures.
- GET /api/v1/events (labelSelector, fieldSelector, limit): Events across every namespace, filtered by field such as the object they are about.
- GET /apis/apps/v1/namespaces/{namespace}/deployments (labelSelector, fieldSelector, limit): A namespace's deployments, with desired, ready and updated replicas.
- GET /apis/apps/v1/deployments (labelSelector, fieldSelector, limit): Deployments across every namespace.
- GET /apis/apps/v1/namespaces/{namespace}/deployments/{name}: One deployment, with its image, strategy, rollout conditions and replicas.
- GET /apis/apps/v1/namespaces/{namespace}/replicasets (labelSelector, fieldSelector, limit): A namespace's replica sets, one per rollout revision, to see what changed and when.
- GET /apis/apps/v1/namespaces/{namespace}/statefulsets (labelSelector, fieldSelector, limit): A namespace's stateful sets, with ready and current replicas.
- GET /apis/apps/v1/namespaces/{namespace}/statefulsets/{name}: One stateful set, with its image, update status and volume claims.
- GET /apis/apps/v1/namespaces/{namespace}/daemonsets (labelSelector, fieldSelector, limit): A namespace's daemon sets, with how many nodes run them and are ready.
- GET /apis/batch/v1/namespaces/{namespace}/jobs (labelSelector, fieldSelector, limit): A namespace's jobs, with how many pods succeeded and failed.
- GET /apis/batch/v1/namespaces/{namespace}/jobs/{name}: One job, with its conditions, failures and timings.
- GET /apis/batch/v1/namespaces/{namespace}/cronjobs (labelSelector, fieldSelector, limit): A namespace's cron jobs, with their schedule and last run.
- GET /apis/autoscaling/v2/namespaces/{namespace}/horizontalpodautoscalers (labelSelector, fieldSelector, limit): A namespace's autoscalers, with their targets, current metrics and replica counts.
- GET /apis/policy/v1/namespaces/{namespace}/poddisruptionbudgets (labelSelector, fieldSelector, limit): A namespace's disruption budgets, with how many pods may be taken down now.
- GET /api/v1/nodes (labelSelector, fieldSelector, limit): The cluster's nodes, with their conditions, capacity, taints and versions.
- GET /api/v1/nodes/{name}: One node, with its conditions such as memory or disk pressure, capacity and allocatable.
- GET /api/v1/namespaces (labelSelector, fieldSelector, limit): The cluster's namespaces and their state.
- GET /api/v1/namespaces/{namespace}/services (labelSelector, fieldSelector, limit): A namespace's services, with their type, ports, selector and addresses.
- GET /api/v1/namespaces/{namespace}/services/{name}: One service, with its ports, selector and load balancer address.
- GET /apis/discovery.k8s.io/v1/namespaces/{namespace}/endpointslices (labelSelector, fieldSelector, limit): Which pods back each service now, and whether each is ready.
- GET /apis/networking.k8s.io/v1/namespaces/{namespace}/ingresses (labelSelector, fieldSelector, limit): A namespace's ingresses, with their hosts, paths, backends and TLS.
- GET /apis/networking.k8s.io/v1/ingresses (labelSelector, fieldSelector, limit): Ingresses across every namespace.
- GET /apis/networking.k8s.io/v1/namespaces/{namespace}/networkpolicies (labelSelector, fieldSelector, limit): A namespace's network policies, which say what traffic pods may send and take.
- GET /api/v1/namespaces/{namespace}/configmaps (labelSelector, fieldSelector, limit): A namespace's config maps, with their data.
- GET /api/v1/namespaces/{namespace}/secrets (labelSelector, fieldSelector, limit): A namespace's secrets, by name and type, never their values.
- GET /api/v1/namespaces/{namespace}/persistentvolumeclaims (labelSelector, fieldSelector, limit): A namespace's volume claims, with their status, size and storage class.
- GET /api/v1/persistentvolumes (labelSelector, fieldSelector, limit): The cluster's persistent volumes, with their status, size and claim.
- GET /api/v1/namespaces/{namespace}/resourcequotas (labelSelector, fieldSelector, limit): A namespace's quotas, with how much of each is used.
- GET /apis/rbac.authorization.k8s.io/v1/namespaces/{namespace}/rolebindings (labelSelector, fieldSelector, limit): Who holds which role in a namespace.
- GET /apis/rbac.authorization.k8s.io/v1/clusterrolebindings (labelSelector, fieldSelector, limit): Who holds which role across the whole cluster.
- GET /apis/rbac.authorization.k8s.io/v1/clusterroles (labelSelector, fieldSelector, limit): The cluster's roles and the permissions each grants.
