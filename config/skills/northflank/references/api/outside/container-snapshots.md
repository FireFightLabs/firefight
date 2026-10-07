# container-snapshots

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/container-snapshots

Gets container snapshots belonging to the team.
Query: per_page, page, cursor, projectId, serviceId, state, trigger.
Permission: Account > Platform > ContainerSnapshots > Read.

### GET /v1/container-snapshots/{snapshotId}

Gets a container snapshot.
Permission: Account > Platform > ContainerSnapshots > Read.

### DELETE /v1/container-snapshots/{snapshotId}

Soft-deletes an unreferenced terminal container snapshot.
Permission: Account > Platform > ContainerSnapshots > Delete.
