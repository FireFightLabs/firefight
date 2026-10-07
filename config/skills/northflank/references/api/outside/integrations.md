# integrations

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/integrations/log-sinks

Gets a list of log sinks added to this account.
Query: per_page, page, cursor.
Permission: Account > Observability > LogSinks > Read.

### POST /v1/integrations/log-sinks

Creates a new log sink.
Body, required: one of {name, sinkType, sinkData.endpoint} or {name, sinkType, sinkData.default_api_key, sinkData.region} or {name, sinkType, sinkData {authenticationStrategy, host, port} or {authenticationStrategy, uri, token}} or {name, sinkType, sinkData.endpoint, sinkData.region, sinkData.bucket, sinkData.compression} or {name, sinkType, sinkData.uri, sinkData.encoding.codec, sinkData.auth {strategy} or {strategy, password}} or {name, sinkType, sinkData.api_key} or {name, sinkType, sinkData.token, sinkData.uri} or {name, sinkType, sinkData.api_key, sinkData.dataset} or {name, sinkType, sinkData.region, sinkData.token} or {name, sinkType, sinkData.api_key, sinkData.endpointType} or {name, sinkType, sinkData.dataset, sinkData.token, sinkData.tokenType} or {name, sinkType, sinkData.accountId, sinkData.licenseKey, sinkData.region} or {name, sinkType, sinkData.endpoint, sinkData.publicKey}.
Body, optional: description, restricted, projects, restrictions, options.
Permission: Account > Observability > LogSinks > Create.

### GET /v1/integrations/log-sinks/{logSinkId}

Gets details about a given log sink.
Permission: Account > Observability > LogSinks > Read.

### DELETE /v1/integrations/log-sinks/{logSinkId}

Deletes a log sink.
Permission: Account > Observability > LogSinks > Delete.

### POST /v1/integrations/log-sinks/{logSinkId}/pause

Pauses a given log sink.
Permission: Account > Observability > LogSinks > Update.

### POST /v1/integrations/log-sinks/{logSinkId}/resume

Resumes a paused log sink.
Permission: Account > Observability > LogSinks > Update.

### POST /v1/integrations/log-sinks/{logSinkId}/settings

Updates the settings for a log sink.
Body, required: one of {sinkType, sinkData} or {sinkType, sinkData.uri, sinkData.encoding, sinkData.auth} or {sinkType, sinkData.dataset}.
Body, optional: restricted, projects, options, resumeLogSink.
Permission: Account > Observability > LogSinks > Update.

### GET /v1/integrations/notifications

Lists notification integrations for the authenticated user, team or org.
Query: per_page, page, cursor.
Permission: Account > Observability > Notifications > Read.

### POST /v1/integrations/notifications

Create a new notification integration.
Body, required: name, type, webhook, events.
Body, optional: secret, restricted, restrictions, projects.
Permission: Account > Observability > Notifications > Create.

### GET /v1/integrations/notifications/{notificationId}

Get details about a notification integration.
Permission: Account > Observability > Notifications > Read.

### POST /v1/integrations/notifications/{notificationId}

Updates a notification integration.
Body, optional: name, webhook, secret, restricted, projects, restrictions, events.
Permission: Account > Observability > Notifications > Update.

### DELETE /v1/integrations/notifications/{notificationId}

Deletes a notification integration.
Permission: Account > Observability > Notifications > Delete.

### GET /v1/integrations/registries

Lists the container registry credentials saved to this account. Does not display secrets.
Query: per_page, page, cursor.
Permission: Account > Cloud > Registries > Read.

### POST /v1/integrations/registries

Adds a new set of container registry credentials to this account.
Body, required: name, provider.
Body, optional: registryUrl, aws, gcp, azure, integrationId, credentials, restrictions, updatedAt, createdAt.
Permission: Account > Cloud > Registries > Create.

### GET /v1/integrations/registries/{credentialId}

Views a set of registry credential data.
Permission: Account > Cloud > Registries > Read.

### PATCH /v1/integrations/registries/{credentialId}

Updates a set of registry credential data.
Body, optional: credentials, restrictions, updatedAt, createdAt.
Permission: Account > Cloud > Registries > Update.

### DELETE /v1/integrations/registries/{credentialId}

Deletes a set of registry credential data.
Permission: Account > Cloud > Registries > Delete.

### GET /v1/integrations/ssh-identities

Lists the SSH identities saved to this account. Does not display SSH public keys.
Query: per_page, page, cursor.
Permission: Account > Platform > Ssh > Read.

### POST /v1/integrations/ssh-identities

Adds a new SSH identity to this account.
Body, required: name.
Body, optional: description, sshPublicKeys[], restrictions, updatedAt, createdAt.
Permission: Account > Platform > Ssh > Create.

### GET /v1/integrations/ssh-identities/{identityId}

Views SSH identity data including public keys.
Permission: Account > Platform > Ssh > Read.

### PUT /v1/integrations/ssh-identities/{identityId}

Creates or updates SSH identity data.
Body, required: name.
Body, optional: description, sshPublicKeys[], restrictions, updatedAt, createdAt.
Permission: Account > Platform > Ssh > Update.

### PATCH /v1/integrations/ssh-identities/{identityId}

Updates SSH identity data.
Body, optional: description, sshPublicKeys[], restrictions, updatedAt, createdAt.
Permission: Account > Platform > Ssh > Update.

### DELETE /v1/integrations/ssh-identities/{identityId}

Deletes an SSH identity.
Permission: Account > Platform > Ssh > Delete.

### GET /v1/integrations/vcs

Lists linked version control providers.
Permission: Account > Git > General > Read.

### POST /v1/integrations/vcs/custom/{customVCSId}/token/{vcsLinkId}

Generate a token for a specific VCS link.
Query: force_refresh.
Permission: Account > Git > Tokens > Read.

### GET /v1/integrations/vcs/repos

Gets a list of repositories accessible to this account.
Query: per_page, page, cursor, vcs_service, self_hosted_vcs_id, account_login, vcs_link_id.
Permission: Account > Git > General > Read.

### GET /v1/integrations/vcs/repos/{vcsService}/{repositoryOwner}/{repositoryName}/branches

Gets a list of branches for the repo.
Query: per_page, page, cursor, vcs_link_id.
Permission: Account > Git > General > Read.
