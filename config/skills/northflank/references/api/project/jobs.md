# jobs

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET jobs

Gets a list of jobs belonging to the project.
Query: per_page, page, cursor.
Permission: Project > Jobs > General > Read.

### POST jobs

Creates a new job (manual or cron based on settings.cron presence).
Body, required: name, billing.deploymentPlan.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], settings.
Permission: Project > Jobs > General > Create.

### PUT jobs

Creates or updates a job (manual or cron based on settings.cron presence).
Body, required: name, billing.deploymentPlan.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], settings.
Permission: Project > Jobs > General > Create.

### GET jobs/{jobId}

Gets information about the given job.
Permission: Project > Jobs > General > Read.

### PATCH jobs/{jobId}

Updates a job (manual or cron based on current type and settings.cron).
Body, optional: description, stageId, tags, billing, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], settings.
Permission: Project > Jobs > General > Update.

### DELETE jobs/{jobId}

Deletes the given job.
Permission: Project > Jobs > General > Delete.

### GET jobs/{jobId}/branches

Gets information about the branches of the given job.
Query: per_page, page, cursor.
Permission: Project > Jobs > General > Read.

### GET jobs/{jobId}/build

Lists builds for the given job.
Query: per_page, page, cursor.
Permission: Project > Jobs > General > Read.

### POST jobs/{jobId}/build

Start a new build for the given job. Given a commit sha, it will build that commit.
Body, optional: sha, overrides.
Permission: Project > Jobs > General > Update.

### GET jobs/{jobId}/build-arguments

Gets the build arguments of the given job. If the API key does not have the permission 'Project > Secrets > General > Read', secrets inherited from secret groups will not be displayed.
Query: show, replaceTemplatedValues.
Permission: Project > Secrets > Jobs > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/build-arguments

Sets build arguments for the given job.
Body, optional: buildArguments, buildFiles, dockerSecretMounts.
Permission: Project > Secrets > Jobs > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### GET jobs/{jobId}/build-arguments/details

Get details about the build arguments accessible by the given job. Also requires the permission 'Project > Secrets > General > Read'.
Permission: Project > Secrets > Jobs > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/build-options

Updates the build options for a given job.
Body, required: one of {dockerfile} or {buildpack} or {}.
Body, optional: pathIgnoreRules, isAllowList, ciIgnoreFlagsEnabled, ciIgnoreFlags, ignoreEmptyCommits, dockerfileTarget, dockerCredentials, includeGitFolder, fullGitClone, enableGitLfs, storage.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### POST jobs/{jobId}/build-source

Updates the version control source for a given job.
Body, optional: projectUrl, projectType, projectBranch, selfHostedVcsId, accountLogin.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### GET jobs/{jobId}/build/{buildId}

Gets information about a build for the job.
Permission: Project > Jobs > General > Update.

### DELETE jobs/{jobId}/build/{buildId}

Aborts the given job build.
Permission: Project > Jobs > General > Update.

### GET jobs/{jobId}/containers

Gets a list of containers for the given job.
Query: per_page, page, cursor, runId.
Permission: Project > Jobs > Deployment > View Observability.

### GET jobs/{jobId}/deployment

Gets information about the deployment of the given job.
Permission: Project > Jobs > General > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/deployment

Updates the deployment settings of the given job.
Body, required: one of {external.imagePath} or {internal} or {}.
Body, optional: docker, buildpack.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### GET jobs/{jobId}/health-checks

Lists the health checks for the given job.
Permission: Project > Jobs > General > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/health-checks

Updates health checks for the given job.
Body, required: healthChecks[].protocol, healthChecks[].type, healthChecks[].initialDelaySeconds, healthChecks[].periodSeconds, healthChecks[].timeoutSeconds, healthChecks[].failureThreshold.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### POST jobs/{jobId}/pause

Pause the given job.
Permission: Project > Jobs > General > Update.

### GET jobs/{jobId}/pull-requests

Gets information about the pull-requests of the given job.
Query: per_page, page, cursor.
Permission: Project > Jobs > General > Read.

### POST jobs/{jobId}/resume

Resumes the given job. Optionally takes several arguments to override resumed settings.
Body, optional: suspended, disabledCI, disabledCD.
Permission: Project > Jobs > General > Update.

### GET jobs/{jobId}/runs

Fetches run history for the given job.
Query: per_page, page, cursor.
Permission: Project > Jobs > General > Read.

### POST jobs/{jobId}/runs

Starts a new job run for the given job.
Body, optional: runtimeEnvironment, runtimeFiles, dockerSecretMounts, billing, deployment.
Permission: Project > Jobs > General > Run Job.

### GET jobs/{jobId}/runs/{runId}

Returns data about the given job run.
Permission: Project > Jobs > General > Read.

### DELETE jobs/{jobId}/runs/{runId}

Aborts the given job run.
Permission: Project > Jobs > General > Update.

### GET jobs/{jobId}/runtime-environment

Returns the runtime environment for the given job. If the API key does not have the permission 'Project > Secrets > General > Read', secrets inherited from secret groups will not be displayed.
Query: show, replaceTemplatedValues.
Permission: Project > Secrets > Jobs > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/runtime-environment

Sets the runtime environment for the given job.
Body, required: runtimeEnvironment.
Body, optional: runtimeFiles.
Permission: Project > Secrets > Jobs > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### GET jobs/{jobId}/runtime-environment/details

Get details about the runtime environment accessible by the given job. Also requires the permission 'Project > Secrets > General > Read'.
Permission: Project > Secrets > Jobs > Read.
Deprecated: Requests should instead use the relevant GET endpoint. Replacement: /jobs/get-job.

### POST jobs/{jobId}/scale

Modifies the scaling settings for the given job.
Body, optional: deploymentPlan, storage.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### POST jobs/{jobId}/settings

Updates settings for the job.
Body, optional: backoffLimit, runOnSourceChange, activeDeadlineSeconds, schedule, concurrencyPolicy.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### POST jobs/{jobId}/suspend

Modify cron job to toggle suspending of its schedule.
Body, optional: suspended.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant PATCH endpoint. Replacement: /jobs/patch-job.

### POST jobs/cron

Creates a new cron job.
Body, required: name, billing.deploymentPlan, backoffLimit.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], runOnSourceChange, activeDeadlineSeconds, schedule, suspended, concurrencyPolicy.
Permission: Project > Jobs > General > Create.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/create-job.

### PUT jobs/cron

Creates or updates a cron job.
Body, required: name, billing.deploymentPlan, backoffLimit.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], runOnSourceChange, activeDeadlineSeconds, schedule, suspended, concurrencyPolicy.
Permission: Project > Jobs > General > Create.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/put-job.

### PATCH jobs/cron/{jobId}

Updates a cron job.
Body, optional: description, stageId, tags, billing, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], backoffLimit, runOnSourceChange, activeDeadlineSeconds, schedule, suspended, concurrencyPolicy.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/patch-job.

### POST jobs/manual

Creates a new manual job that only runs when initiated via the UI, CLI, API or JS client.
Body, required: name, billing.deploymentPlan, backoffLimit.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], runOnSourceChange, activeDeadlineSeconds.
Permission: Project > Jobs > General > Create.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/create-job.

### PUT jobs/manual

Creates or updates a new manual job that only runs when initiated via the UI, CLI, API or JS client.
Body, required: name, billing.deploymentPlan, backoffLimit.
Body, optional: description, stageId, infrastructure, tags, deployment, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], runOnSourceChange, activeDeadlineSeconds.
Permission: Project > Jobs > General > Create.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/put-job.

### PATCH jobs/manual/{jobId}

Updates a new manual job that only runs when initiated via the UI, CLI, API or JS client.
Body, optional: description, stageId, tags, billing, disabledCI, buildConfiguration, buildSettings, runtimeEnvironment, runtimeFiles, buildArguments, buildFiles, dockerSecretMounts, healthChecks[], backoffLimit, runOnSourceChange, activeDeadlineSeconds.
Permission: Project > Jobs > General > Update.
Deprecated: Requests should instead use the relevant type-agnostic job endpoint. Replacement: /jobs/patch-job.
