# backup-destinations

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/backup-destinations

Lists the backup destinations saved to this account. Does not display secrets.
Query: per_page, page, cursor.
Permission: Account > Platform > BackupDestinations > Read.

### POST /v1/backup-destinations

Adds a new backup destination to this account.
Body, required: name, type, usage, prefix, credentials.bucketName, credentials.region, credentials.endpoint.
Body, optional: description.
Permission: Account > Platform > BackupDestinations > Create.

### GET /v1/backup-destinations/{backupDestinationId}

View a backup destination, including secrets.
Permission: Account > Platform > BackupDestinations > Read.

### PATCH /v1/backup-destinations/{backupDestinationId}

Updates a backup destination.
Body, optional: name, description, credentials.
Permission: Account > Platform > BackupDestinations > Update.

### DELETE /v1/backup-destinations/{backupDestinationId}

Delete a backup destination.
Permission: Account > Platform > BackupDestinations > Delete.

### GET /v1/backup-destinations/{backupDestinationId}/backups

Lists the backups associated with a backup destinations.
Query: per_page, page, cursor.
Permission: Account > Platform > BackupDestinations > Read.
