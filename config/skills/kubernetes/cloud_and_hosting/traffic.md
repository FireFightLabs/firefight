---
name: kubernetes_traffic
when: A Kubernetes workload's pods are running but its Service or Ingress returns errors, times out, or sends traffic nowhere
tools: [list_resources, resource_status, list_events, search_logs, workload_logs]
references: [debug/debug-service.md, networking/ingress.md, configuration/probes.md]
---
1. Call `list_resources` for the namespace. Find the ingress that serves the hostname, the service it routes to, and the selector that service picks pods with. The resource map shows the same chain from hostname to ingress to service to workload.
2. Check the service selects the pods: its selector has to match the labels on the workload's pod template, in the same namespace. A selector that matches nothing leaves the service with no endpoints, and every request to it fails. A typo or a label changed in a new revision is the usual cause.
3. Call `resource_status` on the workload. Only ready pods receive a service's traffic, so pods running but not ready, such as a failing readiness probe, mean requests have nowhere to go even though nothing crashed.
4. Check the ports: the service's port has to reach the container's port through its target port, and the ingress has to name the service and a port it has.
5. Read the pods' own lines with `search_logs`. No request reaching the app points at the routing above. Requests arriving and failing point at the app or something it calls.
6. Call `list_events` with `type` Warning for errors from the ingress controller or the load balancer, when they write events.
