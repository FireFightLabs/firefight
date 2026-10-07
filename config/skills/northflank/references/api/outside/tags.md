# tags

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/tags

List the resource tags for this entity.
Query: per_page, page, cursor.
Permission: Account > Platform > Tags > Read.

### POST /v1/tags

Add a new resource tag for this entity.
Body, required: name.
Body, optional: useAsInfrastructureLabel, useSpotNodes, useOnDemandNodes, nodeAffinities[], sandboxing, color, description.
Permission: Account > Platform > Tags > Create.

### PUT /v1/tags

Update or create a resource tag.
Body, required: name.
Body, optional: useAsInfrastructureLabel, useSpotNodes, useOnDemandNodes, nodeAffinities[], sandboxing, color, description.
Permission: Account > Platform > Tags > Update.

### GET /v1/tags/{resourceTagId}

View details for a given resource tag.
Permission: Account > Platform > Tags > Read.

### PATCH /v1/tags/{resourceTagId}

Patch a resource tag.
Body, optional: useAsInfrastructureLabel, useSpotNodes, useOnDemandNodes, nodeAffinities[], sandboxing, color, description.
Permission: Account > Platform > Tags > Update.

### DELETE /v1/tags/{resourceTagId}

Delete a resource tag.
Permission: Account > Platform > Tags > Delete.
