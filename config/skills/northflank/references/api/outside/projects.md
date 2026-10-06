# projects

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/projects

Lists projects for the authenticated user or team.
Query: per_page, page, cursor.
Permission: Project > Projects > Manage > Read.

### POST /v1/projects

Creates a new project.
Body, required: name.
Body, optional: description, color, region, networking, clusterId.
Permission: Project > Projects > Manage > Create.

### PUT /v1/projects

Creates or updates a project.
Body, required: name.
Body, optional: description, color, region, networking, clusterId.
Permission: Project > Projects > Manage > Create.

### GET /v1/projects/{projectId}

Get information about the given project.
Permission: Project > Projects > Manage > Read.

### PATCH /v1/projects/{projectId}

Updates a project.
Body, optional: description, color, networking.
Permission: Project > Projects > Manage > Update.

### DELETE /v1/projects/{projectId}

Delete the given project. Fails if the project isn't empty.
Query: delete_child_objects.
Permission: Project > Projects > Manage > Delete.
