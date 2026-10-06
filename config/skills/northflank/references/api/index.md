# API endpoints

Every endpoint in the provider's API, as its own API client (@northflank/js-client 0.11.0) defines them, with the method and path. An operation that is not listed here is not in the API, so it cannot be done through it.

Paths inside /v1/projects/{projectId}/ are written after it. The rest are written in full. Each area's file, named under it, gives each endpoint's purpose, the body fields it requires and takes, its query options and the permission it needs.

## Paths written after /v1/projects/{projectId}/

### addons (project/addons.md)

- GET addons
- POST addons
- PUT addons
- GET addons/{addonId}
- PATCH addons/{addonId}
- DELETE addons/{addonId}
- GET addons/{addonId}/backup-schedules
- POST addons/{addonId}/backup-schedules
- DELETE addons/{addonId}/backup-schedules/{scheduleId}
- GET addons/{addonId}/backups
- POST addons/{addonId}/backups
- GET addons/{addonId}/backups/{backupId}
- DELETE addons/{addonId}/backups/{backupId}
- POST addons/{addonId}/backups/{backupId}/abort
- POST addons/{addonId}/backups/{backupId}/abort-restore
- GET addons/{addonId}/backups/{backupId}/download-link
- POST addons/{addonId}/backups/{backupId}/restore
- GET addons/{addonId}/backups/{backupId}/restores
- POST addons/{addonId}/backups/{backupId}/retain
- GET addons/{addonId}/containers
- GET addons/{addonId}/credentials
- POST addons/{addonId}/import
- POST addons/{addonId}/network-settings
- POST addons/{addonId}/pause
- POST addons/{addonId}/reset
- POST addons/{addonId}/restart
- GET addons/{addonId}/restores
- POST addons/{addonId}/resume
- POST addons/{addonId}/scale
- POST addons/{addonId}/secret-rotation
- POST addons/{addonId}/secret-rotation/finalise
- POST addons/{addonId}/security
- GET addons/{addonId}/version
- POST addons/{addonId}/version

### external-addons (project/external-addons.md)

- GET external-addons
- POST external-addons
- GET external-addons/{externalAddonId}
- PATCH external-addons/{externalAddonId}
- DELETE external-addons/{externalAddonId}

### harnesses (project/harnesses.md)

- GET harnesses
- POST harnesses
- PUT harnesses
- GET harnesses/{harnessId}
- PATCH harnesses/{harnessId}
- DELETE harnesses/{harnessId}
- POST harnesses/{harnessId}/pause
- POST harnesses/{harnessId}/restart
- POST harnesses/{harnessId}/resume

### jobs (project/jobs.md)

- GET jobs
- POST jobs
- PUT jobs
- GET jobs/{jobId}
- PATCH jobs/{jobId}
- DELETE jobs/{jobId}
- GET jobs/{jobId}/branches
- GET jobs/{jobId}/build
- POST jobs/{jobId}/build
- GET jobs/{jobId}/build-arguments
- POST jobs/{jobId}/build-arguments
- GET jobs/{jobId}/build-arguments/details
- POST jobs/{jobId}/build-options
- POST jobs/{jobId}/build-source
- GET jobs/{jobId}/build/{buildId}
- DELETE jobs/{jobId}/build/{buildId}
- GET jobs/{jobId}/containers
- GET jobs/{jobId}/deployment
- POST jobs/{jobId}/deployment
- GET jobs/{jobId}/health-checks
- POST jobs/{jobId}/health-checks
- POST jobs/{jobId}/pause
- GET jobs/{jobId}/pull-requests
- POST jobs/{jobId}/resume
- GET jobs/{jobId}/runs
- POST jobs/{jobId}/runs
- GET jobs/{jobId}/runs/{runId}
- DELETE jobs/{jobId}/runs/{runId}
- GET jobs/{jobId}/runtime-environment
- POST jobs/{jobId}/runtime-environment
- GET jobs/{jobId}/runtime-environment/details
- POST jobs/{jobId}/scale
- POST jobs/{jobId}/settings
- POST jobs/{jobId}/suspend
- POST jobs/cron
- PUT jobs/cron
- PATCH jobs/cron/{jobId}
- POST jobs/manual
- PUT jobs/manual
- PATCH jobs/manual/{jobId}

### llm-model-deployments (project/llm-model-deployments.md)

- GET llm-model-deployments
- POST llm-model-deployments
- GET llm-model-deployments/{llmModelDeploymentId}
- POST llm-model-deployments/{llmModelDeploymentId}
- DELETE llm-model-deployments/{llmModelDeploymentId}

### pipelines (project/pipelines.md)

- GET pipelines
- GET pipelines/{pipelineId}
- GET pipelines/{pipelineId}/preview-envs
- POST pipelines/{pipelineId}/preview-envs
- GET pipelines/{pipelineId}/preview-envs/previews
- DELETE pipelines/{pipelineId}/preview-envs/previews/{previewId}
- GET pipelines/{pipelineId}/preview-envs/runs
- POST pipelines/{pipelineId}/preview-envs/runs
- GET pipelines/{pipelineId}/preview-envs/runs/{templateRunId}
- GET pipelines/{pipelineId}/release-flows/{stage}
- POST pipelines/{pipelineId}/release-flows/{stage}
- GET pipelines/{pipelineId}/release-flows/{stage}/runs
- POST pipelines/{pipelineId}/release-flows/{stage}/runs
- GET pipelines/{pipelineId}/release-flows/{stage}/runs/{runId}
- POST pipelines/{pipelineId}/release-flows/{stage}/runs/{runId}/abort

### preview-blueprints (project/preview-blueprints.md)

- GET preview-blueprints
- POST preview-blueprints
- GET preview-blueprints/{previewBlueprintId}
- POST preview-blueprints/{previewBlueprintId}
- DELETE preview-blueprints/{previewBlueprintId}
- GET preview-blueprints/{previewBlueprintId}/previews
- DELETE preview-blueprints/{previewBlueprintId}/previews/{previewId}
- POST preview-blueprints/{previewBlueprintId}/previews/{previewId}/pause
- POST preview-blueprints/{previewBlueprintId}/previews/{previewId}/reset
- POST preview-blueprints/{previewBlueprintId}/previews/{previewId}/resume
- GET preview-blueprints/{previewBlueprintId}/runs
- POST preview-blueprints/{previewBlueprintId}/runs
- GET preview-blueprints/{previewBlueprintId}/runs/{runId}
- POST preview-blueprints/{previewBlueprintId}/runs/{runId}/abort

### secrets (project/secrets.md)

- GET secrets
- POST secrets
- PUT secrets
- GET secrets/{secretId}
- POST secrets/{secretId}
- PATCH secrets/{secretId}
- DELETE secrets/{secretId}
- GET secrets/{secretId}/addons/{addonId}
- POST secrets/{secretId}/addons/{addonId}
- DELETE secrets/{secretId}/addons/{addonId}
- GET secrets/{secretId}/details

### services (project/services.md)

- GET services
- GET services/{serviceId}
- DELETE services/{serviceId}
- GET services/{serviceId}/branches
- GET services/{serviceId}/build
- POST services/{serviceId}/build
- GET services/{serviceId}/build-arguments
- POST services/{serviceId}/build-arguments
- GET services/{serviceId}/build-arguments/details
- DELETE services/{serviceId}/build-cache
- POST services/{serviceId}/build-options
- POST services/{serviceId}/build-source
- GET services/{serviceId}/build/{buildId}
- DELETE services/{serviceId}/build/{buildId}
- GET services/{serviceId}/containers
- GET services/{serviceId}/deployment
- POST services/{serviceId}/deployment
- GET services/{serviceId}/deployments
- GET services/{serviceId}/health-checks
- POST services/{serviceId}/health-checks
- POST services/{serviceId}/pause
- GET services/{serviceId}/per-replica-volumes
- DELETE services/{serviceId}/per-replica-volumes/volume/{volumeId}
- DELETE services/{serviceId}/per-replica-volumes/volume/{volumeId}/replica/{ordinal}
- GET services/{serviceId}/ports
- POST services/{serviceId}/ports
- GET services/{serviceId}/pull-requests
- POST services/{serviceId}/restart
- POST services/{serviceId}/resume
- GET services/{serviceId}/rollout
- POST services/{serviceId}/rollout/configuration
- POST services/{serviceId}/rollout/promote
- POST services/{serviceId}/rollout/rollback
- GET services/{serviceId}/runtime-environment
- POST services/{serviceId}/runtime-environment
- GET services/{serviceId}/runtime-environment/details
- POST services/{serviceId}/scale
- POST services/{serviceId}/snapshots
- POST services/build
- PUT services/build
- PATCH services/build/{serviceId}
- POST services/combined
- PUT services/combined
- PATCH services/combined/{serviceId}
- POST services/deployment
- PUT services/deployment
- PATCH services/deployment/{serviceId}

### volumes (project/volumes.md)

- GET volumes
- POST volumes
- GET volumes/{volumeId}
- POST volumes/{volumeId}
- DELETE volumes/{volumeId}
- POST volumes/{volumeId}/attach
- GET volumes/{volumeId}/backup-schedules
- POST volumes/{volumeId}/backup-schedules
- DELETE volumes/{volumeId}/backup-schedules/{scheduleId}
- GET volumes/{volumeId}/backups
- POST volumes/{volumeId}/backups
- GET volumes/{volumeId}/backups/{backupId}
- DELETE volumes/{volumeId}/backups/{backupId}
- POST volumes/{volumeId}/detach

### workflows (project/workflows.md)

- GET workflows
- POST workflows
- GET workflows/{workflowId}
- POST workflows/{workflowId}
- GET workflows/{workflowId}/runs
- POST workflows/{workflowId}/runs
- GET workflows/{workflowId}/runs/{runId}
- POST workflows/{workflowId}/runs/{runId}/abort

## Paths outside /v1/projects/{projectId}/, written in full

### addon-types (outside/addon-types.md)

- GET /v1/addon-types

### auth (outside/auth.md)

- GET /v1/auth

### backup-destinations (outside/backup-destinations.md)

- GET /v1/backup-destinations
- POST /v1/backup-destinations
- GET /v1/backup-destinations/{backupDestinationId}
- PATCH /v1/backup-destinations/{backupDestinationId}
- DELETE /v1/backup-destinations/{backupDestinationId}
- GET /v1/backup-destinations/{backupDestinationId}/backups

### billing (outside/billing.md)

- GET /v1/billing/invoices
- GET /v1/billing/invoices/{invoiceId}
- GET /v1/billing/usage
- GET /v1/billing/usage/{timestamp}

### cloud-providers (outside/cloud-providers.md)

- GET /v1/cloud-providers
- GET /v1/cloud-providers/clusters
- POST /v1/cloud-providers/clusters
- PUT /v1/cloud-providers/clusters
- GET /v1/cloud-providers/clusters/{clusterId}
- PATCH /v1/cloud-providers/clusters/{clusterId}
- DELETE /v1/cloud-providers/clusters/{clusterId}
- GET /v1/cloud-providers/clusters/{clusterId}/nodes
- POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/cordon
- POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/drain
- POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/uncordon
- GET /v1/cloud-providers/integrations
- POST /v1/cloud-providers/integrations
- PUT /v1/cloud-providers/integrations
- GET /v1/cloud-providers/integrations/{integrationId}
- PATCH /v1/cloud-providers/integrations/{integrationId}
- DELETE /v1/cloud-providers/integrations/{integrationId}
- GET /v1/cloud-providers/node-types
- GET /v1/cloud-providers/regions

### container-snapshots (outside/container-snapshots.md)

- GET /v1/container-snapshots
- GET /v1/container-snapshots/{snapshotId}
- DELETE /v1/container-snapshots/{snapshotId}

### directory-groups (outside/directory-groups.md)

- GET /v1/directory-groups
- GET /v1/directory-groups/{groupId}/members

### dns-id (outside/dns-id.md)

- GET /v1/dns-id

### domains (outside/domains.md)

- GET /v1/domains
- POST /v1/domains
- GET /v1/domains/{domain}
- PATCH /v1/domains/{domain}
- DELETE /v1/domains/{domain}
- GET /v1/domains/{domain}/certificate
- POST /v1/domains/{domain}/import
- POST /v1/domains/{domain}/subdomains
- PUT /v1/domains/{domain}/subdomains
- GET /v1/domains/{domain}/subdomains/{subdomain}
- DELETE /v1/domains/{domain}/subdomains/{subdomain}
- POST /v1/domains/{domain}/subdomains/{subdomain}/assign
- DELETE /v1/domains/{domain}/subdomains/{subdomain}/assign
- POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/disable
- POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/enable
- POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/purge
- POST /v1/domains/{domain}/subdomains/{subdomain}/certificate/import
- PATCH /v1/domains/{domain}/subdomains/{subdomain}/geo-routing
- GET /v1/domains/{domain}/subdomains/{subdomain}/paths
- POST /v1/domains/{domain}/subdomains/{subdomain}/paths
- GET /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}
- POST /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}
- DELETE /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}
- POST /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}/assign
- DELETE /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}/assign
- POST /v1/domains/{domain}/subdomains/{subdomain}/verify
- POST /v1/domains/{domain}/verify

### egress-ips (outside/egress-ips.md)

- GET /v1/egress-ips
- POST /v1/egress-ips
- PUT /v1/egress-ips
- GET /v1/egress-ips/{egressIpId}
- PATCH /v1/egress-ips/{egressIpId}
- DELETE /v1/egress-ips/{egressIpId}

### gradual-rollout-strategies (outside/gradual-rollout-strategies.md)

- GET /v1/gradual-rollout-strategies
- POST /v1/gradual-rollout-strategies
- PUT /v1/gradual-rollout-strategies
- GET /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}
- PATCH /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}
- DELETE /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}

### integrations (outside/integrations.md)

- GET /v1/integrations/log-sinks
- POST /v1/integrations/log-sinks
- GET /v1/integrations/log-sinks/{logSinkId}
- DELETE /v1/integrations/log-sinks/{logSinkId}
- POST /v1/integrations/log-sinks/{logSinkId}/pause
- POST /v1/integrations/log-sinks/{logSinkId}/resume
- POST /v1/integrations/log-sinks/{logSinkId}/settings
- GET /v1/integrations/notifications
- POST /v1/integrations/notifications
- GET /v1/integrations/notifications/{notificationId}
- POST /v1/integrations/notifications/{notificationId}
- DELETE /v1/integrations/notifications/{notificationId}
- GET /v1/integrations/registries
- POST /v1/integrations/registries
- GET /v1/integrations/registries/{credentialId}
- PATCH /v1/integrations/registries/{credentialId}
- DELETE /v1/integrations/registries/{credentialId}
- GET /v1/integrations/ssh-identities
- POST /v1/integrations/ssh-identities
- GET /v1/integrations/ssh-identities/{identityId}
- PUT /v1/integrations/ssh-identities/{identityId}
- PATCH /v1/integrations/ssh-identities/{identityId}
- DELETE /v1/integrations/ssh-identities/{identityId}
- GET /v1/integrations/vcs
- POST /v1/integrations/vcs/custom/{customVCSId}/token/{vcsLinkId}
- GET /v1/integrations/vcs/repos
- GET /v1/integrations/vcs/repos/{vcsService}/{repositoryOwner}/{repositoryName}/branches

### load-balancers (outside/load-balancers.md)

- GET /v1/load-balancers
- POST /v1/load-balancers
- PUT /v1/load-balancers
- GET /v1/load-balancers/{loadBalancerId}
- PATCH /v1/load-balancers/{loadBalancerId}
- DELETE /v1/load-balancers/{loadBalancerId}

### network-policies (outside/network-policies.md)

- POST /v1/network-policies
- GET /v1/network-policies/{networkPolicyId}
- PATCH /v1/network-policies/{networkPolicyId}
- DELETE /v1/network-policies/{networkPolicyId}

### org-members (outside/org-members.md)

- GET /v1/org-members

### org-roles (outside/org-roles.md)

- GET /v1/org-roles
- POST /v1/org-roles
- PUT /v1/org-roles
- GET /v1/org-roles/{roleId}
- PATCH /v1/org-roles/{roleId}
- DELETE /v1/org-roles/{roleId}
- GET /v1/org-roles/{roleId}/members
- POST /v1/org-roles/{roleId}/members
- DELETE /v1/org-roles/{roleId}/members/{memberId}

### plans (outside/plans.md)

- GET /v1/plans

### projects (outside/projects.md)

- GET /v1/projects
- POST /v1/projects
- PUT /v1/projects
- GET /v1/projects/{projectId}
- PATCH /v1/projects/{projectId}
- DELETE /v1/projects/{projectId}

### regions (outside/regions.md)

- GET /v1/regions

### secrets (outside/secrets.md)

- GET /v1/secrets
- POST /v1/secrets
- PUT /v1/secrets
- GET /v1/secrets/{secretId}
- PATCH /v1/secrets/{secretId}
- DELETE /v1/secrets/{secretId}
- POST /v1/secrets/{secretId}/trigger-dependents

### tags (outside/tags.md)

- GET /v1/tags
- POST /v1/tags
- PUT /v1/tags
- GET /v1/tags/{resourceTagId}
- PATCH /v1/tags/{resourceTagId}
- DELETE /v1/tags/{resourceTagId}

### teams (outside/teams.md)

- GET /v1/teams
- POST /v1/teams
- GET /v1/teams/{teamId}
- PATCH /v1/teams/{teamId}
- DELETE /v1/teams/{teamId}
- GET /v1/teams/{teamId}/members
- POST /v1/teams/{teamId}/members
- DELETE /v1/teams/{teamId}/members/{memberId}
- GET /v1/teams/{teamId}/roles
- POST /v1/teams/{teamId}/roles
- PUT /v1/teams/{teamId}/roles
- GET /v1/teams/{teamId}/roles/{roleId}
- PATCH /v1/teams/{teamId}/roles/{roleId}
- DELETE /v1/teams/{teamId}/roles/{roleId}
- GET /v1/teams/{teamId}/roles/{roleId}/members
- POST /v1/teams/{teamId}/roles/{roleId}/members
- DELETE /v1/teams/{teamId}/roles/{roleId}/members/{memberId}

### templates (outside/templates.md)

- GET /v1/templates
- POST /v1/templates
- GET /v1/templates/{templateId}
- POST /v1/templates/{templateId}
- DELETE /v1/templates/{templateId}
- GET /v1/templates/{templateId}/runs
- POST /v1/templates/{templateId}/runs
- GET /v1/templates/{templateId}/runs/{templateRunId}
- POST /v1/templates/{templateId}/runs/{templateRunId}/abort

### tokens (outside/tokens.md)

- GET /v1/tokens
- POST /v1/tokens/{tokenId}/keys
- DELETE /v1/tokens/{tokenId}/keys/{keyId}

### workload-identities (outside/workload-identities.md)

- GET /v1/workload-identities
- POST /v1/workload-identities
- GET /v1/workload-identities/{workloadIdentityId}
- PATCH /v1/workload-identities/{workloadIdentityId}
- DELETE /v1/workload-identities/{workloadIdentityId}
