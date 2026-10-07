# workflows

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET workflows

Lists all workflows for a project.
Query: per_page, page, cursor.
Permission: Project > Workflows > General > Read.

### POST workflows

Create a workflow.
Body, required: name, apiVersion, spec.
Body, optional: arguments, gitops, $schema, description, richInputs, options, teardownSpec, argumentOverrides, crossProjectAccess, stageId, triggers, project.
Permission: Project > Workflows > General > Create.

### GET workflows/{workflowId}

Gets details about a workflow.
Permission: Project > Workflows > General > Read.

### POST workflows/{workflowId}

Updates a workflow.
Body, required: name, apiVersion, spec.
Body, optional: arguments, gitops, $schema, description, richInputs, options, teardownSpec, argumentOverrides, crossProjectAccess, stageId, triggers, project.
Permission: Project > Workflows > General > Update.

### GET workflows/{workflowId}/runs

Lists runs of a workflow.
Query: per_page, page, cursor.
Permission: Project > Workflows > Runs > Read.

### POST workflows/{workflowId}/runs

Runs a given workflow with given arguments. This endpoint can be used as part of a CI pipeline to automatically trigger a release process.
Body, optional: name, description, arguments, overrides, releaseNodeOverrides.
Permission: Project > Workflows > Runs > Start.

### GET workflows/{workflowId}/runs/{runId}

Get information about the given workflow run.
Permission: Project > Workflows > Runs > Read.

### POST workflows/{workflowId}/runs/{runId}/abort

Abort the given workflow run.
Permission: Project > Workflows > Runs > Abort.
