# network-policies

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### POST /v1/network-policies

Creates a new network policy for this account.
Body, required: name, spec.
Body, optional: description.
Permission: Account > Networking > NetworkPolicies > Create.

### GET /v1/network-policies/{networkPolicyId}

Get details of a network policy.
Permission: Account > Networking > NetworkPolicies > Read.

### PATCH /v1/network-policies/{networkPolicyId}

Updates an existing network policy.
Body, optional: name, description, spec.
Permission: Account > Networking > NetworkPolicies > Update.

### DELETE /v1/network-policies/{networkPolicyId}

Deletes a network policy and removes all associated CNPs from the cluster.
Permission: Account > Networking > NetworkPolicies > Delete.
