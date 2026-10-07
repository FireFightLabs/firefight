# volumes

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET volumes

Gets a list of volumes belonging to the project.
Query: per_page, page, cursor.
Permission: Project > Volumes > General > Read.

### POST volumes

Creates a volume with the specified payload.
Body, required: name, mounts[].containerMountPath, spec.accessMode, spec.storageSize.
Body, optional: stageId, tags, source, owningObject, attachedObjects[], backupSchedules[].
Permission: Project > Volumes > General > Create.

### GET volumes/{volumeId}

Retrieve a volume.
Permission: Project > Volumes > General > Read.

### POST volumes/{volumeId}

Update volume mounts and storage size.
Body, optional: mounts[], spec, backupSchedules[].
Permission: Project > Volumes > General > Update.

### DELETE volumes/{volumeId}

Deletes this volume and its associated data.
Permission: Project > Volumes > General > Delete.

### POST volumes/{volumeId}/attach

Attach a volume.
Body, optional: owningObject, nfObject.
Permission: Project > Volumes > General > Update.

### GET volumes/{volumeId}/backup-schedules

Gets details about a volume's backup schedules.
Query: per_page, page, cursor.
Permission: Project > Volumes > Backups > Read.

### POST volumes/{volumeId}/backup-schedules

Create a new snapshot backup schedule for a volume.
Body, required: scheduling.interval, scheduling.minute, retentionTime.
Permission: Project > Volumes > Backups > Create.

### DELETE volumes/{volumeId}/backup-schedules/{scheduleId}

Deletes a snapshot backup schedule for a volume.
Permission: Project > Volumes > Backups > Delete.

### GET volumes/{volumeId}/backups

Get list of backups associated with a volume.
Query: per_page, page, cursor.
Permission: Project > Volumes > Backups > Read.

### POST volumes/{volumeId}/backups

Initiates a backup for a given volume.
Body, required: name.
Body, optional: description.
Permission: Project > Volumes > Backups > Create.

### GET volumes/{volumeId}/backups/{backupId}

Get details for a specific volume backup.
Permission: Project > Volumes > Backups > Read.

### DELETE volumes/{volumeId}/backups/{backupId}

Delete the volume backup.
Permission: Project > Volumes > Backups > Delete.

### POST volumes/{volumeId}/detach

Detach a volume.
Body, required: nfObject.id, nfObject.type.
Permission: Project > Volumes > General > Update.
