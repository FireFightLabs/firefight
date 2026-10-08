# services

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET services

Gets a list of services belonging to the project.
Query: per_page, page, cursor.
Permission: Project > Services > General > Read.

### GET services/{serviceId}

Gets information about the given service.
Permission: Project > Services > General > Read.

### DELETE services/{serviceId}
