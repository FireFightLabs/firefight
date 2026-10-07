# org-roles

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/org-roles

Gets a list of platform roles for the authenticated org.
Query: per_page, page, cursor.
Permission: Organisation > Admin > Roles > Read.

### POST /v1/org-roles

Creates a new platform role for the authenticated org.
Body, required: name.
Body, optional: description, permissions, restrictions, directoryGroups.
Permission: Organisation > Admin > Roles > Manage.

### PUT /v1/org-roles

Creates role or updates all user-editable fields on a platform role for the authenticated org.
Body, required: name.
Body, optional: description, permissions, restrictions, directoryGroups.
Permission: Organisation > Admin > Roles > Manage.

### GET /v1/org-roles/{roleId}

Gets details about a specific org platform role.
Permission: Organisation > Admin > Roles > Read.

### PATCH /v1/org-roles/{roleId}

Partially updates a platform role for the authenticated org.
Body, optional: description, permissions, restrictions, directoryGroups.
Permission: Organisation > Admin > Roles > Manage.

### DELETE /v1/org-roles/{roleId}

Deletes a platform role from the authenticated org.
Permission: Organisation > Admin > Roles > Manage.

### GET /v1/org-roles/{roleId}/members

Gets a list of members assigned to a platform role in the authenticated org.
Query: per_page, page, cursor, type, userIds.
Permission: Organisation > Admin > Roles > Read.

### POST /v1/org-roles/{roleId}/members

Adds a user to a platform role in the authenticated org.
Body, required: userId.
Permission: Organisation > Admin > Roles > Manage.

### DELETE /v1/org-roles/{roleId}/members/{memberId}

Removes a user from a platform role in the authenticated org.
Permission: Organisation > Admin > Roles > Manage.
