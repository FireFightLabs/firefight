# harnesses

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET harnesses

Gets a list of harnesses belonging to the project.
Query: per_page, page, cursor, projectUrl, projectType, projectBranch.
Permission: Project > Harnesses > General > Read.

### POST harnesses

Creates a new harness.
Body, required: name, billing.deploymentPlan, deployment, harness.type.
Body, optional: description, stageId, tags, ports[], source, additionalRepositories[], branchData, repositoryData, runtimeEnvironment, runtimeFiles.
Permission: Project > Harnesses > General > Create.

### PUT harnesses

Creates or updates a harness.
Body, required: name, billing.deploymentPlan, deployment, harness.type.
Body, optional: description, stageId, tags, ports[], source, additionalRepositories[], repositoryData, runtimeEnvironment, runtimeFiles.
Query: acknowledgeActiveSessions.
Permission: Project > Harnesses > General > Create.

### GET harnesses/{harnessId}

Gets information about the given harness.
Permission: Project > Harnesses > General > Read.

### PATCH harnesses/{harnessId}

Updates a harness.
Body, optional: description, stageId, tags, billing, deployment, ports[], source, additionalRepositories[], runtimeEnvironment, runtimeFiles, harness.
Query: acknowledgeActiveSessions.
Permission: Project > Harnesses > General > Update.

### DELETE harnesses/{harnessId}

Deletes the given harness.
Query: acknowledgeActiveSessions.
Permission: Project > Harnesses > General > Delete.

### POST harnesses/{harnessId}/pause

Pauses the given harness, scaling its deployment to zero.
Query: acknowledgeActiveSessions.
Permission: Project > Harnesses > General > Update.

### POST harnesses/{harnessId}/restart

Restarts the given harness.
Query: acknowledgeActiveSessions.
Permission: Project > Harnesses > General > Update.

### POST harnesses/{harnessId}/resume

Resumes the given harness, restoring its deployment.
Permission: Project > Harnesses > General > Update.
