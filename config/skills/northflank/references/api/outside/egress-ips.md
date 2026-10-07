# egress-ips

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/egress-ips

Gets a list of egress IPs belonging to the team.
Query: per_page, page, cursor.
Permission: Account > Networking > EgressIps > Read.

### POST /v1/egress-ips

Creates a new egress IP.
Body, required: name, spec.provisioningMode, spec.region.
Body, optional: description.
Permission: Account > Networking > EgressIps > Create.

### PUT /v1/egress-ips

Creates or updates an egress IP.
Body, required: name, spec.provisioningMode, spec.region.
Body, optional: description.
Permission: Account > Networking > EgressIps > Create.

### GET /v1/egress-ips/{egressIpId}

Gets information about the given egress IP.
Permission: Account > Networking > EgressIps > Read.

### PATCH /v1/egress-ips/{egressIpId}

Updates an egress IP.
Body, optional: name, description, spec.
Permission: Account > Networking > EgressIps > Update.

### DELETE /v1/egress-ips/{egressIpId}

Deletes the given egress IP.
Permission: Account > Networking > EgressIps > Delete.
