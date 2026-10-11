---
name: azure_api
when: A question about Azure that the other Azure tools do not answer, such as a Web App's deployment slots, a Container App's revisions and replicas, App Service plans, an AKS cluster's node pools, load balancers, Application Gateway, Front Door, a Key Vault's settings, a resource's health, a resource group's deployments, or anything else Azure Resource Manager reads, and finding out whether Azure offers a read at all
tools: [api_read, list_resources, run_history, deployment_log]
references: [api/web/index.md, api/app/index.md, api/sql/index.md, api/dbforpostgresql/index.md, api/dbformysql/index.md, api/compute/index.md, api/containerservice/index.md, api/network/index.md, api/storage/index.md, api/insights/index.md, api/resources/index.md, api/resourcehealth/index.md, api/keyvault/index.md, api/cache/index.md, api/cdn/index.md, api/operationalinsights/index.md]
---
`api_read` sends a GET to Azure Resource Manager and answers what Azure said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through the rollback, restart and scale tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_resources` for what is on the map, with each resource's id, and `run_history` and `deployment_log` for a Web App's or Function app's past deployments and what each wrote. Reach for `api_read` for the rest.
2. Find the path in the resource provider's API reference before the first call, not by guessing: read api/<provider>/index.md for the provider (use_skill with this skill and that reference), such as api/app/index.md for Container Apps or api/web/index.md for App Service, which lists every read it offers with its path, its api-version and what it answers. When no reference lists a read for the question, Azure does not offer one. Say so, and give the steps in the portal instead.
3. Set `path` to the path the reference writes with its ids filled in, starting from a resource's id as `list_resources` shows it, such as /subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.App/containerApps/<app>/revisions. Put api-version, the version the reference names, and every other parameter in `query`, never in the path. A path stays inside this connection's subscription, and another one is refused.
4. A list answers one page, and its nextLink names the next. Read on by taking the path and the parameters nextLink gives, such as $skiptoken, into a new call.
5. Keys, connection strings and links signed with a SAS come back as their names, and Resource Manager never hands a secret's value to a read. Say which setting to check in the portal when the question needs a value.
6. A refusal for want of a permission is the workspace's to fix. Name the action Azure's refusal gives, such as Microsoft.App/containerApps/revisions/read, and the role that holds it, such as Reader.

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- insights: GET /subscriptions/{subscriptionId}/providers/Microsoft.Insights/eventtypes/management/values ($filter, $select, api-version=2015-04-01): The activity log of who changed what, between two times.
- resourcehealth: GET /subscriptions/{subscriptionId}/providers/Microsoft.ResourceHealth/events ($filter, api-version=2025-05-01): Azure outages and planned maintenance that touch the subscription.
- resourcehealth: GET /subscriptions/{subscriptionId}/providers/Microsoft.ResourceHealth/availabilityStatuses ($filter, api-version=2025-05-01): Whether each resource is available, and why not.
- insights: GET /subscriptions/{subscriptionId}/providers/Microsoft.Insights/metrics (region, metricnamespace, metricnames, timespan, interval, aggregation, $filter, api-version=2024-02-01): A metric's values over a time range, such as CPU or requests.
- insights: GET /subscriptions/{subscriptionId}/providers/Microsoft.Insights/metricAlerts (api-version=2026-01-01): Metric alert rules with their condition and whether each is on.
- resources: GET /subscriptions/{subscriptionId}/resources ($filter, api-version=2025-04-01): Every resource, filtered by type, tag or name.
- resources: GET /subscriptions/{subscriptionId}/resourcegroups/{resourceGroupName}/providers/Microsoft.Resources/deployments ($filter, api-version=2026-06-01): Template deployments in a resource group with their state.
- web: GET /subscriptions/{subscriptionId}/providers/Microsoft.Web/sites (api-version=2026-07-15): App Service apps with their state and host names.
- web: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/deployments (api-version=2026-07-15): An app's deployments with their status and author.
- web: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/deployments/{id}/log (api-version=2026-07-15): The log of one deployment of an app.
- web: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Web/sites/{name}/config/web (api-version=2026-07-15): An app's runtime settings, such as stack version and health check path.
- web: GET /subscriptions/{subscriptionId}/providers/Microsoft.Web/serverfarms (api-version=2026-07-15): App Service plans with their tier, size and instance count.
- app: GET /subscriptions/{subscriptionId}/providers/Microsoft.App/containerApps (api-version=2026-07-01): Container Apps with their state and latest revision.
- app: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.App/containerApps/{containerAppName}/revisions ($filter, api-version=2026-07-01): A Container App's revisions with their health and traffic share.
- app: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.App/containerApps/{containerAppName}/revisions/{revisionName}/replicas (api-version=2026-07-01): A revision's replicas with each container's state and restarts.
- containerservice: GET /subscriptions/{subscriptionId}/providers/Microsoft.ContainerService/managedClusters (api-version=2026-07-01): AKS clusters with their version and state.
- containerservice: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ContainerService/managedClusters/{resourceName}/agentPools (api-version=2026-07-01): An AKS cluster's node pools with their size, count and version.
- compute: GET /subscriptions/{subscriptionId}/providers/Microsoft.Compute/virtualMachines ($filter, api-version=2026-04-01): Virtual machines with their size.
- compute: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.Compute/virtualMachines/{vmName}/instanceView (api-version=2026-04-01): A virtual machine's power state and recent status messages.
- network: GET /subscriptions/{subscriptionId}/providers/Microsoft.Network/loadBalancers (api-version=2026-03-01): Load balancers with their frontends, backend pools, rules and probes.
- network: GET /subscriptions/{subscriptionId}/providers/Microsoft.Network/applicationGateways (api-version=2026-03-01): Application Gateways with their state, listeners and backend pools.
- sql: GET /subscriptions/{subscriptionId}/providers/Microsoft.Sql/servers (api-version=2025-01-01): Azure SQL servers with their state and version.
- dbforpostgresql: GET /subscriptions/{subscriptionId}/providers/Microsoft.DBforPostgreSQL/flexibleServers (api-version=2025-08-01): PostgreSQL flexible servers with their state, version and size.
- dbformysql: GET /subscriptions/{subscriptionId}/providers/Microsoft.DBforMySQL/flexibleServers (api-version=2024-12-30): MySQL flexible servers with their state, version and size.
- cache: GET /subscriptions/{subscriptionId}/providers/Microsoft.Cache/redis (api-version=2024-11-01): Redis caches with their state, size and version.
- keyvault: GET /subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.KeyVault/vaults/{vaultName}/secrets (api-version=2026-05-15): A Key Vault's secrets by name and expiry, never their values.
