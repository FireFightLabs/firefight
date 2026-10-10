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
