# templates

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/templates

Get a list of templates.
Query: per_page, page, cursor.
Permission: Account > Templates > General > Read.

### POST /v1/templates

Create a template.
Body, required: one of {name, apiVersion, spec} or {name, gitops.vcsService, gitops.repoUrl, gitops.branch, gitops.filePath}.
Body, optional: description, arguments, teardownSpec, argumentOverrides, options, project.
Permission: Account > Templates > General > Create.

### GET /v1/templates/{templateId}

Get information about the given template.
Query: per_page, page, cursor.
Permission: Account > Templates > General > Read.

### POST /v1/templates/{templateId}

Update a template.
Body, required: one of {name, apiVersion, spec} or {name, gitops.vcsService, gitops.repoUrl, gitops.branch, gitops.filePath}.
Body, optional: description, options, arguments, $schema, teardownSpec, argumentOverrides.
Permission: Account > Templates > General > Update.

### DELETE /v1/templates/{templateId}

Delete a template.
Permission: Account > Templates > General > Delete.

### GET /v1/templates/{templateId}/runs

Get a list of template runs.
Query: per_page, page, cursor, status, concluded.
Permission: Account > Templates > General > Read.

### POST /v1/templates/{templateId}/runs

Run a template.
Body, optional: arguments.
Permission: Account > Templates > General > Run.

### GET /v1/templates/{templateId}/runs/{templateRunId}

Get information about the given template run.
Permission: Account > Templates > General > Read.

### POST /v1/templates/{templateId}/runs/{templateRunId}/abort

Abort the given template run.
Permission: Account > Templates > Runs > Abort.
