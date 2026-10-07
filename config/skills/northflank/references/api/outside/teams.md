# teams

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/teams

Gets a list of teams belonging to the authenticated org.
Query: per_page, page, cursor.
Permission: Organisation > Team > General > Read.

### POST /v1/teams

Creates a new team belonging to the authenticated org.
Body, required: name, email.
Body, optional: description.
Permission: Organisation > Team > General > Create.

### GET /v1/teams/{teamId}

Gets information about a team belonging to the authenticated org.
Permission: Organisation > Team > General > Read.

### PATCH /v1/teams/{teamId}

Updates the description of a team belonging to the authenticated org.
Body, optional: description.
Permission: Organisation > Team > General > Update.

### DELETE /v1/teams/{teamId}

Deletes a team belonging to the authenticated org.
Permission: Organisation > Team > General > Delete.

### GET /v1/teams/{teamId}/members

Gets a list of members belonging to a team.
Query: per_page, page, cursor.
Permission: Account > Admin > Members > Read.

### POST /v1/teams/{teamId}/members

Invites a user to a team.
Body, required: email.
Body, optional: roles.
Permission: Account > Admin > Members > Manage.

### DELETE /v1/teams/{teamId}/members/{memberId}

Removes a member from a team.
Permission: Account > Admin > Members > Manage.

### GET /v1/teams/{teamId}/roles

Gets a list of platform roles for a team.
Query: per_page, page, cursor.
Permission: Account > Admin > Roles > Read.

### POST /v1/teams/{teamId}/roles

Creates a new platform role for a team.
Body, required: name.
Body, optional: description, permissions, restrictions.
Permission: Account > Admin > Roles > Manage.

### PUT /v1/teams/{teamId}/roles

Creates role or updates all user-editable fields on a platform role.
Body, required: name.
Body, optional: description, permissions, restrictions.
Permission: Account > Admin > Roles > Manage.

### GET /v1/teams/{teamId}/roles/{roleId}

Gets details about a specific platform role.
Permission: Account > Admin > Roles > Read.

### PATCH /v1/teams/{teamId}/roles/{roleId}

Updates a platform role for a team.
Body, optional: description, permissions, restrictions.
Permission: Account > Admin > Roles > Manage.

### DELETE /v1/teams/{teamId}/roles/{roleId}

Deletes a platform role from a team.
Permission: Account > Admin > Roles > Manage.

### GET /v1/teams/{teamId}/roles/{roleId}/members

Gets a list of members assigned to a platform role in a team.
Query: per_page, page, cursor, userIds.
Permission: Account > Admin > Roles > Read.

### POST /v1/teams/{teamId}/roles/{roleId}/members

Adds a user to a platform role in a team.
Body, required: userId.
Permission: Account > Admin > Roles > Manage.

### DELETE /v1/teams/{teamId}/roles/{roleId}/members/{memberId}

Removes a user from a platform role in a team.
Permission: Account > Admin > Roles > Manage.
