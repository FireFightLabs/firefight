---
name: digitalocean_api
when: A question about DigitalOcean that the other DigitalOcean tools do not answer, such as an app's alerts or domains, one deployment's progress, load balancers, volumes, Kubernetes clusters, firewalls, VPCs, a database's configuration, replicas or backups, projects, or anything else DigitalOcean's API reads, and finding out whether the API offers a read at all
tools: [api_read, list_resources, app_logs]
references: [api/index.md]
---
`api_read` sends a GET to any path of DigitalOcean's API and answers what DigitalOcean said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, restart, scale and reboot tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is there. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read DigitalOcean's API offers by area, then the area's page it names for the parameters and the fields each read answers. Paths start /v2, as the reference writes them. When the reference lists no read for the question, the API does not offer it. Say so, and give the steps in the control panel instead.
3. Fill the path's ids from `list_resources` or an earlier answer, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass per_page, at most 200, and page for the next while the answer's links say there is a next page.
5. Passwords, keys and secret values come back hidden, and a cluster's kubeconfig, the registry's Docker credentials and an app's log addresses are never read. Read an app's logs with `app_logs`. When DigitalOcean answers that the token lacks a scope, say which read scope to add to the token in DigitalOcean, such as kubernetes:read.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /v2/apps (page, per_page): The account's App Platform apps, with each one's active deployment and phase.
- GET /v2/apps/{id}: One app, with its spec, active and in progress deployments, and live URL.
- GET /v2/apps/{app_id}/deployments (page, per_page): An app's deployments, newest first, with each one's phase, cause and progress.
- GET /v2/apps/{app_id}/deployments/{deployment_id}: One deployment, with its phase, steps, cause and any error.
- GET /v2/apps/{app_id}/health: The health of an app's components, with their running and failing instances.
- GET /v2/apps/{app_id}/alerts: An app's alerts, with each one's rule and phase.
- GET /v2/apps/{app_id}/events (page, per_page): An app's events, such as deploys, autoscaling and restarts, newest first.
- GET /v2/monitoring/metrics/apps/cpu_percentage (app_id, start, end): An app component's CPU use over a time range.
- GET /v2/monitoring/metrics/apps/memory_percentage (app_id, start, end): An app component's memory use over a time range.
- GET /v2/monitoring/metrics/apps/restart_count (app_id, start, end): How often an app component restarted over a time range.
- GET /v2/droplets (per_page, page, type): The account's Droplets, with each one's status, size, region and addresses.
- GET /v2/droplets/{droplet_id}: One Droplet, with its status, size, image, networks and features.
- GET /v2/droplets/{droplet_id}/actions (per_page, page): Actions taken on a Droplet, such as reboots, resizes and power cycles, newest first.
- GET /v2/monitoring/metrics/droplet/cpu (host_id, start, end): A Droplet's CPU use over a time range.
- GET /v2/monitoring/metrics/droplet/memory_available (host_id, start, end): A Droplet's available memory over a time range.
- GET /v2/monitoring/metrics/droplet/filesystem_free (host_id, start, end): A Droplet's free disk space over a time range.
- GET /v2/droplets/autoscale (per_page, page): The account's Droplet autoscale pools, with their size and status.
- GET /v2/droplets/autoscale/{autoscale_pool_id}/history (per_page, page): An autoscale pool's scaling events, newest first.
- GET /v2/actions (per_page, page): Every action taken across the account, newest first, with its type, status and resource.
- GET /v2/kubernetes/clusters (per_page, page): The account's Kubernetes clusters, with their status, version and node pools.
- GET /v2/kubernetes/clusters/{cluster_id}: One Kubernetes cluster, with its status, version, node pools and maintenance window.
- GET /v2/kubernetes/clusters/{cluster_id}/node_pools: A cluster's node pools, with their size, node count and each node's status.
- GET /v2/kubernetes/clusters/{cluster_id}/status_messages (since): A cluster's status messages, such as control plane problems, newest first.
- GET /v2/databases: The account's database clusters, with their engine, status, size and region.
- GET /v2/databases/{database_cluster_uuid}: One database cluster, with its status, engine version, nodes and maintenance window.
- GET /v2/databases/{database_cluster_uuid}/events: A database cluster's events, such as failovers, resizes and maintenance.
- GET /v2/databases/{database_cluster_uuid}/backups: A database cluster's backups, with when each was taken and its size.
- GET /v2/databases/{database_cluster_uuid}/replicas: A database cluster's read replicas, with their status and region.
- GET /v2/databases/{database_cluster_uuid}/firewall: Which sources may reach a database cluster.
- GET /v2/databases/{database_cluster_uuid}/users: A database cluster's users, by name and role, never their passwords.
- GET /v2/load_balancers (per_page, page): The account's load balancers, with their status, rules, health checks and Droplets.
- GET /v2/load_balancers/{lb_id}: One load balancer, with its status, forwarding rules and health check.
- GET /v2/monitoring/metrics/load_balancer/droplets_health_checks (lb_id, start, end): Whether a load balancer's Droplets passed their health checks over a time range.
- GET /v2/monitoring/metrics/load_balancer/frontend_http_responses (lb_id, start, end): A load balancer's responses by status code over a time range.
- GET /v2/monitoring/alerts (per_page, page): The account's alert policies, with what each watches and where it notifies.
- GET /v2/uptime/checks (per_page, page): The account's uptime checks, with their target and regions.
- GET /v2/uptime/checks/{check_id}/state: Whether an uptime check is up or down now, by region, with its latency.
- GET /v2/domains/{domain_name}/records (type, per_page, page): A domain's DNS records, with each one's type, name, value and TTL.
- GET /v2/certificates (per_page, page): The account's certificates, with their domains, state and expiry.
- GET /v2/customers/my/balance: The account's balance and usage so far this month.
