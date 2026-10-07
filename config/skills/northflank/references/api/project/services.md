# services

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET services

Gets a list of services belonging to the project.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### GET services/{serviceId}

Gets information about the given service.
Permission: Project > Services > General > Read.

### DELETE services/{serviceId}

Deletes the given service.
Query: delete_child_objects.
Permission: Project > Services > General > Delete.

### GET services/{serviceId}/branches

Gets information about the branches of the given service.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### GET services/{serviceId}/build

Lists the builds for the service.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### POST services/{serviceId}/build

Start a new build for the given combined or build service. Git build services require a branch or pull request. Bundle build services require a bundle URL and accept an optional branch and revision.
Body, required: one of {bundleUrl} or {}.
Body, optional: branch, sha, overrides, pullRequestId.
Permission: Project > Services > General > Update.

### GET services/{serviceId}/build-arguments

Gets the build arguments of the given service. If the API key does not have the permission 'Project > Secrets > General > Read', secrets inherited from secret groups will not be displayed.
Query: show, replaceTemplatedValues.
Permission: Project > Secrets > Services > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/build-arguments

Sets the build arguments for the given service.
Body, optional: buildArguments, buildFiles, dockerSecretMounts.
Permission: Project > Secrets > Services > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### GET services/{serviceId}/build-arguments/details

Get details about the build arguments accessible by the given service. Also requires the permission 'Project > Secrets > General > Read'.
Permission: Project > Secrets > Services > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### DELETE services/{serviceId}/build-cache

Clears the build cache of a given combined or build service.
Permission: Project > Services > General > Update.

### POST services/{serviceId}/build-options

Updates the build options for a given service.
Body, required: one of {dockerfile} or {buildpack} or {}.
Body, optional: prRestrictions, branchRestrictions, crossProjectAccess, pathIgnoreRules, isAllowList, ciIgnoreFlagsEnabled, ciIgnoreFlags, ignoreEmptyCommits, dockerfileTarget, dockerCredentials, includeGitFolder, fullGitClone, enableGitLfs, storage.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### POST services/{serviceId}/build-source

Updates the version control source for a given build or combined service.
Body, optional: projectUrl, projectType, projectBranch, selfHostedVcsId, accountLogin.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### GET services/{serviceId}/build/{buildId}

Gets information about a build for the service.
Permission: Project > Services > General > Read.

### DELETE services/{serviceId}/build/{buildId}

Aborts the given service build.
Permission: Project > Services > General > Update.

### GET services/{serviceId}/containers

Gets a list of containers for the given service.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### GET services/{serviceId}/deployment

Gets information about the deployment of the given service.
Permission: Project > Services > General > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/deployment

Updates the deployment settings of the given service.
Body, required: one of {external.imagePath} or {internal} or {}.
Body, optional: docker, buildpack.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### GET services/{serviceId}/deployments

Lists the deployments of the given service, newest first. For services using a gradual rollout strategy each deployment also reports the release type it was created as.
Query: per_page, page, cursor, releaseType.
Permission: Project > Services > General > Read.

### GET services/{serviceId}/health-checks

Lists the health checks for the given service.
Permission: Project > Services > General > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/health-checks

Updates health checks for the given service.
Body, required: healthChecks[].protocol, healthChecks[].type, healthChecks[].initialDelaySeconds, healthChecks[].periodSeconds, healthChecks[].timeoutSeconds, healthChecks[].failureThreshold.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### POST services/{serviceId}/pause

Pause the given service.
Permission: Project > Services > General > Update.

### GET services/{serviceId}/per-replica-volumes

Lists the per-replica statefulSet volumes for the given service.
Permission: Project > Services > General > Read.

### DELETE services/{serviceId}/per-replica-volumes/volume/{volumeId}

Fully deletes a removed per-replica statefulSet volume for the given service: all of its orphaned PVCs and the volume definition. The volume must first be removed from the service.
Permission: Project > Services > General > Delete.

### DELETE services/{serviceId}/per-replica-volumes/volume/{volumeId}/replica/{ordinal}

Deletes one orphaned per-replica statefulSet volume PVC — a scaled-down ordinal, or a replica of a removed volume. Replicas still bound to a running instance are refused with 409.
Permission: Project > Services > General > Delete.

### GET services/{serviceId}/ports

Lists the ports for the given service.
Permission: Project > Services > General > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/ports

Updates the list of ports for the given service.
Body, required: ports[].protocol, ports[].name, ports[].internalPort.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### GET services/{serviceId}/pull-requests

Gets information about the pull-requests of the given service.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### POST services/{serviceId}/restart

Restarts the given service.
Permission: Project > Services > General > Update.

### POST services/{serviceId}/resume

Resumes the given service. Optionally takes several arguments to override resumed settings.
Body, optional: instances, disabledCI, disabledCD, enableAutoscaling.
Permission: Project > Services > General > Update.

### GET services/{serviceId}/rollout

Gets the active gradual rollout of the given service, including the traffic configuration, the stable and canary deployments, and previous traffic configurations.
Permission: Project > Services > General > Read.

### POST services/{serviceId}/rollout/configuration

Updates the traffic split of the active gradual rollout. Only percentage based rollouts can be reconfigured. Setting the canary to 100% promotes the rollout.
Body, required: canaryPercentage, stablePercentage.
Permission: Project > Services > General > Update.

### POST services/{serviceId}/rollout/promote

Promotes the canary deployment of the active gradual rollout to stable, routing all traffic to it. This is idempotent: promoting an already promoted rollout succeeds without changing anything.
Permission: Project > Services > General > Update.

### POST services/{serviceId}/rollout/rollback

Ends the active gradual rollout and redeploys the service from a previous deployment. Use the list service deployments endpoint to find the deployment to roll back to.
Body, required: deployment.
Permission: Project > Services > General > Update.

### GET services/{serviceId}/runtime-environment

Gets the runtime environment of the given service. If the API key does not have the permission 'Project > Secrets > General > Read', secrets inherited from secret groups will not be displayed.
Query: show, replaceTemplatedValues.
Permission: Project > Secrets > Services > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/runtime-environment

Sets the runtime environment for the given service.
Body, required: runtimeEnvironment.
Body, optional: runtimeFiles.
Permission: Project > Secrets > Services > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### GET services/{serviceId}/runtime-environment/details

Get details about the runtime environment accessible by the given service. Also requires the permission 'Project > Secrets > General > Read'.
Permission: Project > Secrets > Services > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /services/get-service.

### POST services/{serviceId}/scale

Modifies the scaling settings for the given service.
Body, optional: instances, deploymentPlan, storage, gracePeriodSeconds.
Permission: Project > Services > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /services/patch-combined-service.

### POST services/{serviceId}/snapshots

Schedules a snapshot of a running deployment service pod. When no pod is provided, the service must have exactly one eligible pod. Repeated requests for an active pod return the existing snapshot.
Body, optional: podName, backupDestinationId.
Permission: Account > Platform > ContainerSnapshots > Create.

### POST services/build

Creates a new build service.
Body, required: name, billing, buildSettings {dockerfile.dockerFilePath, dockerfile.dockerWorkDir} or {buildpack}.
Body, optional: description, stageId, tags, infrastructure, disabledCI, buildSource, vcsData, buildConfiguration, buildArguments, buildFiles, dockerSecretMounts.
Permission: Project > Services > General > Create.

### PUT services/build

Creates or updates a build service.
Body, required: name, billing, buildSettings {dockerfile.dockerFilePath, dockerfile.dockerWorkDir} or {buildpack}.
Body, optional: description, stageId, tags, infrastructure, disabledCI, buildSource, vcsData, buildConfiguration, buildArguments, buildFiles, dockerSecretMounts.
Permission: Project > Services > General > Create.

### PATCH services/build/{serviceId}

Updates a build service.
Body, optional: description, stageId, tags, billing, disabledCI, buildSource, vcsData, buildSettings, buildConfiguration, buildArguments, buildFiles, dockerSecretMounts.
Permission: Project > Services > General > Update.

### POST services/combined

Creates a new combined service.
Body, required: name, billing.deploymentPlan, deployment.instances, buildSettings {dockerfile.dockerFilePath, dockerfile.dockerWorkDir} or {buildpack}.
Body, optional: description, stageId, tags, infrastructure, ports[], disabledCI, buildSource, vcsData, bundleData, buildConfiguration, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], loadBalancing, autoscaling, createOptions.
Permission: Project > Services > General > Create.

### PUT services/combined

Creates or updates a combined service.
Body, required: name, billing.deploymentPlan, deployment.instances, buildSettings {dockerfile.dockerFilePath, dockerfile.dockerWorkDir} or {buildpack}.
Body, optional: description, stageId, tags, infrastructure, ports[], disabledCI, buildSource, vcsData, bundleData, buildConfiguration, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], loadBalancing, autoscaling, createOptions.
Permission: Project > Services > General > Create.

### PATCH services/combined/{serviceId}

Updates a combined service.
Body, optional: description, stageId, tags, billing, deployment, ports[], disabledCI, buildSource, vcsData, bundleData, buildSettings, buildConfiguration, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], loadBalancing, autoscaling.
Permission: Project > Services > General > Update.

### POST services/deployment

Creates a new deployment service.
Body, required: name, billing.deploymentPlan, deployment {instances, internal} or {instances, external.imagePath} or {instances}.
Body, optional: description, stageId, tags, infrastructure, ports[], runtimeEnvironment, runtimeFiles, healthChecks[], loadBalancing, autoscaling, createOptions.
Permission: Project > Services > General > Create.

### PUT services/deployment

Creates or updates a deployment service.
Body, required: name, billing.deploymentPlan, deployment {instances, internal} or {instances, external.imagePath} or {instances}.
Body, optional: description, stageId, tags, infrastructure, ports[], runtimeEnvironment, runtimeFiles, healthChecks[], loadBalancing, autoscaling, createOptions.
Permission: Project > Services > General > Create.

### PATCH services/deployment/{serviceId}

Updates a deployment service.
Body, optional: description, stageId, tags, billing, deployment, ports[], runtimeEnvironment, runtimeFiles, healthChecks[], loadBalancing, autoscaling.
Permission: Project > Services > General > Update.
