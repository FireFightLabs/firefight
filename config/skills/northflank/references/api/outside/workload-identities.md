# workload-identities

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/workload-identities

Lists the workload identities saved to this account.
Query: per_page, page, cursor.
Permission: Account > Cloud > WorkloadIdentities > Read.

### POST /v1/workload-identities

Creates a new workload identity on this account. For managed roles using automatic provider setup, installation of the cloud resources is triggered automatically unless `noInstall=true` is passed.
Body, required: name, spec.providerLinkId, spec.roleMode, spec.provider {type, policyDocument.Version, policyDocument.Statement[].Effect, policyDocument.Statement[].Action, policyDocument.Statement[].Resource} or {type, existingRoleArn} or {type, permissions} or {type, existingRoleAudience, existingRoleImpersonationUrl}, spec.restrictions.
Body, optional: description, priority, updatedAt, createdAt.
Query: noInstall.
Permission: Account > Cloud > WorkloadIdentities > Create.

### GET /v1/workload-identities/{workloadIdentityId}

Retrieves a workload identity by ID.
Permission: Account > Cloud > WorkloadIdentities > Read.

### PATCH /v1/workload-identities/{workloadIdentityId}

Updates a workload identity. For managed roles using automatic provider setup, installation of the cloud resources is triggered automatically unless `noInstall=true` is passed.
Body, optional: description, priority, updatedAt, createdAt, spec.
Query: noInstall.
Permission: Account > Cloud > WorkloadIdentities > Update.

### DELETE /v1/workload-identities/{workloadIdentityId}

Deletes a workload identity.
Permission: Account > Cloud > WorkloadIdentities > Delete.
