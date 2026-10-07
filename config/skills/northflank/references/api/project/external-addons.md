# external-addons

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET external-addons

Gets a list of external addons belonging to the project.
Query: per_page, page, cursor, resourceType, status.
Permission: Project > ExternalAddons > General > Read.

### POST external-addons

Creates a new external addon (third-party cloud resource provisioned via OpenTofu).
Body, required: name.
Body, optional: description, tags, environmentId, spec.
Permission: Project > ExternalAddons > General > Create.

### GET external-addons/{externalAddonId}

Gets information about the given external addon.
Permission: Project > ExternalAddons > General > Read.

### PATCH external-addons/{externalAddonId}

Updates configuration for an external addon.
Body, optional: description, tags, environmentId, spec.
Permission: Project > ExternalAddons > General > Update.

### DELETE external-addons/{externalAddonId}

Deletes an external addon and destroys the associated cloud resource.
Permission: Project > ExternalAddons > General > Delete.
