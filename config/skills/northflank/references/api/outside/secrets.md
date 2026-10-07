# secrets

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/secrets

Gets a list of global secrets.
Query: per_page, page, cursor.
Permission: Account > GlobalSecrets > Secrets > Read.

### POST /v1/secrets

Creates a global secret with the specified payload.
Body, required: name, type.
Body, optional: description, secrets, gitops, dependents.
Permission: Account > GlobalSecrets > Secrets > Create.

### PUT /v1/secrets

Creates or updates a global secret with the specified payload.
Body, required: name, type.
Body, optional: description, secrets, gitops, dependents.
Query: runDependents, idempotencyKey.
Permission: Account > GlobalSecrets > Secrets > Create.

### GET /v1/secrets/{secretId}

Get a global secret including its contents.
Permission: undefined.

### PATCH /v1/secrets/{secretId}

Updates a global secret with the specified payload.
Body, optional: description, secrets, gitops, dependents.
Query: runDependents, idempotencyKey.
Permission: undefined.

### DELETE /v1/secrets/{secretId}

Delete a global secret.
Permission: undefined.

### POST /v1/secrets/{secretId}/trigger-dependents

Runs the templates configured under the global secret’s dependents (when enabled).
Query: idempotencyKey.
Permission: Account > Templates > General > Run.
