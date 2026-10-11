---
name: railway_api
when: A question about Railway that the other Railway tools do not answer, such as a project's environments and services, one deployment by its id, volumes and their backups, domains, TCP proxies, deployment triggers or the workspace's members, and finding out whether Railway's API offers a read at all
tools: [api_read, list_resources]
references: [api/index.md]
---
`api_read` runs one GraphQL query against Railway's public API and answers what Railway said. It only reads, so it never needs the person's go ahead and works while investigating and watching. A mutation or a subscription is refused. Changes go through the restart, rollback and scale in railway_fixes, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for the services, databases and cron jobs. Reach for `api_read` for the rest.
2. Find the fields in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every query field Railway's API offers by area, then the area's page it names for the arguments each takes. When the reference lists no field for the question, Railway's API does not offer it. Say so, and give the steps in Railway's dashboard instead.
3. Write the `query` with its values as GraphQL variables, such as query($id: String!) { project(id: $id) { name } }, and pass them in `variables`. Name ids from `list_resources` or an earlier answer. Reads stay in the projects this connection reads, so name the project, and a query reaching another one is refused.
4. A list is a connection. Pass first, and to read on, pass the pageInfo's endCursor as after.
5. A query that reads variables, an environment's config or tokens comes back as names only, with every value hidden. When the question needs a value, say which variable to check in Railway.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- deployments (input, first, after): Deployments of a project, environment or service, newest first, with each one's status.
- deployment (id): One deployment, with its status, commit, creator and instances.
- deploymentEvents (id, first): The steps a deployment went through, such as build, deploy and healthcheck, with timing.
- deploymentInstanceExecutions (input, first): A deployment's running instances and how each one ended, such as crashed or exited.
- deploymentTriggers (projectId, environmentId, serviceId): What deploys a service on its own, such as a repository branch.
- buildLogs (deploymentId, filter, startDate, endDate, limit): A deployment's build log lines, between two times, narrowed by a filter.
- deploymentLogs (deploymentId, filter, startDate, endDate, limit): A deployment's runtime log lines, between two times, narrowed by a filter.
- environmentLogs (environmentId, filter, anchorDate, beforeLimit, afterLimit): Log lines across every service in an environment around a moment.
- httpLogs (deploymentId, filter, anchorDate, beforeLimit, afterLimit): A deployment's HTTP requests around a moment, with their status, path and duration.
- networkFlowLogs (environmentId, serviceId, filter, anchorDate): Network connections into and out of an environment's services.
- metrics (projectId, serviceId, environmentId, measurements, startDate, endDate, groupBy): CPU, memory, network and disk of a service or volume over a time range.
- httpMetrics (serviceId, environmentId, startDate, endDate, statusCode, path): A service's request rate over time, narrowed by path, method or status.
- httpMetricsGroupedByStatus (serviceId, environmentId, startDate, endDate): A service's requests over time, split by status code.
- httpDurationMetrics (serviceId, environmentId, startDate, endDate, path): A service's response times over time, as percentiles.
- traces (serviceId, environmentId, startDate, endDate, filter): A service's traces between two times, narrowed by a filter.
- projects (workspaceId, first, after): Every project in a workspace.
- project (id): One project, with its environments and services.
- environments (projectId, isEphemeral): A project's environments, including preview ones.
- environment (id, projectId): One environment, with its service instances and their latest deployments.
- service (id): One service, with its source and its instances in each environment.
- serviceInstance (serviceId, environmentId): A service in one environment, with its start command, region, replicas and healthcheck.
- serviceInstanceLimits (serviceId, environmentId): The CPU and memory a service may use in one environment.
- variables (projectId, environmentId, serviceId): The variables of a service or environment, by name, never their values.
- domains (projectId, environmentId, serviceId): A service's Railway and custom domains in one environment.
- domainStatus (id, projectId): A custom domain's DNS and certificate status.
- customDomain (id, projectId): One custom domain, with its target and status.
- tcpProxies (serviceId, environmentId): A service's TCP proxies and their public ports.
- privateNetworks (environmentId): An environment's private networks.
- volumeInstance (id): One volume in an environment, with its size, usage and mount path.
- volumeInstanceBackupList (volumeInstanceId): A volume's backups and when each was taken.
- volumeInstanceBackupScheduleList (volumeInstanceId): A volume's backup schedules.
- auditLogs (workspaceId, filter, first, after): The workspace's audit log, who changed what and when.
- events (projectId, environmentId, filter, first): A project's or environment's event history, newest first.
- projectMembers (projectId): A project's members and their roles.
- workspace (workspaceId): One workspace, with its members, plan and settings.
- apiTokens (after, first): The account's API tokens by name and when each was made, never their values.
- projectTokens (projectId): A project's tokens by name and environment, never their values.
- notificationRules (workspaceId, projectId): The workspace's or project's notification rules, what each alerts on and where.
- usage (workspaceId, projectId, measurements, startDate, endDate): Resource usage of a workspace or project over a time range.
- estimatedUsage (workspaceId, projectId, measurements): The estimated usage and cost of a workspace or project this billing period.
