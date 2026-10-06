# secrets

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET secrets

Gets a list of project secrets belonging to the project.
Query: per_page, page, cursor.
Permission: Project > Secrets > SecretGroups > List.

### POST secrets

Creates a project secret with the specified payload.
Body, required: name, secretType, priority.
Body, optional: description, stageId, tags, type, restrictions, addonDependencies[], externalAddonDependencies[], secrets.
Permission: Project > Secrets > SecretGroups > Create.

### PUT secrets

Creates or updates a project secret with the specified payload.
Body, required: name, secretType, priority.
Body, optional: description, stageId, tags, type, restrictions, addonDependencies[], externalAddonDependencies[], secrets.
Permission: Project > Secrets > SecretGroups > Create.

### GET secrets/{secretId}

View a project secret including its contents.
Query: show.
Permission: undefined.

### POST secrets/{secretId}

Update a project secret.
Body, optional: description, priority, restrictions, addonDependencies[], externalAddonDependencies[], type, secretType, secrets.
Permission: undefined.

### PATCH secrets/{secretId}

Updates a project secret with the specified payload.
Body, optional: description, stageId, tags, type, secretType, priority, restrictions, addonDependencies[], externalAddonDependencies[], secrets.
Permission: undefined.

### DELETE secrets/{secretId}

Delete a project secret.
Permission: undefined.

### GET secrets/{secretId}/addons/{addonId}

Get details about a given addon link.
Permission: undefined.

### POST secrets/{secretId}/addons/{addonId}

Link an addon to a project secret or edit the settings of the linked addon.
Body, required: keys[].keyName.
Permission: undefined.

### DELETE secrets/{secretId}/addons/{addonId}

Unlinks an addon from the project secret.
Permission: undefined.
Deprecated: This API endpoint is deprecated.

### GET secrets/{secretId}/details

View a project secret with details about its linked addons.
Permission: undefined.
