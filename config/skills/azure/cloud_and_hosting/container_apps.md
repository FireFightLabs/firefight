---
name: azure_container_apps
when: A Container App fails to start, restarts, answers with errors, or broke after a new revision
tools: [recent_deploys, resource_status, search_logs, query_metrics, rollback, restart]
references: [container-apps/troubleshoot-container-start-failures.md, container-apps/troubleshoot-health-probe-failures.md, container-apps/revisions.md, container-apps/revisions-manage.md, container-apps/traffic-splitting.md, container-apps/log-options.md]
---
1. Call `recent_deploys` for its revisions, each with whether it is active, its health, running state, replicas, traffic share and image. A newest revision that is unhealthy or failed while an older one still takes the traffic means the new one never started.
2. Read the platform's events with `search_logs` with stream system, for image pulls that failed, containers that exited, probes that failed and replicas that were restarted. Then read what the app printed with the app stream.
3. The causes Microsoft lists for a container that does not start: the image cannot be pulled, the app listens on a port other than the ingress target port, it crashes on start for a missing setting or secret, or its health probes fail before it is ready.
4. Call `query_metrics` with `metrics` cpu, memory, requests and http_5xx. Memory near its limit with restarts points at the container being killed for memory.
5. To go back to a revision that worked, offer `rollback` with `to` set to its name. This needs the app in multiple revision mode, and sends it all the traffic. In single revision mode, the fix is deploying the earlier image again. For replicas stuck in a bad state, offer `restart`, which restarts every active revision.
6. Say which revision, the error, the evidence and the fix.
