# directory-groups

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/directory-groups

Lists the Directory Sync directory groups for the authenticated org.
Permission: Organisation > Admin > Roles > Read.

### GET /v1/directory-groups/{groupId}/members

Lists the users who are members of the org via a specific Directory Sync group.
Query: per_page, page, cursor.
Permission: Organisation > Admin > Members > Read.
