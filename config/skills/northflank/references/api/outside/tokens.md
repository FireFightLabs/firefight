# tokens

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/tokens

Lists API tokens belonging to the authenticated org or team, newest first. Only active tokens are returned unless the `all` query parameter is set.
Query: per_page, page, cursor, all.
Permission: Account > Admin > ApiTokens > Read.

### POST /v1/tokens/{tokenId}/keys

Creates a new key for an API token and sets all other keys to expire.
Body, optional: otherKeysExpiresAt.
Permission: Account > Admin > ApiTokens > Update.

### DELETE /v1/tokens/{tokenId}/keys/{keyId}

Removes a key from an API token.
Permission: Account > Admin > ApiTokens > Update.
