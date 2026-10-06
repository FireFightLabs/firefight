# cloud-providers

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/cloud-providers

Lists supported cloud providers.
Permission: undefined.

### GET /v1/cloud-providers/clusters

Lists clusters for the authenticated user or team.
Query: per_page, page, cursor.
Permission: Account > Cloud > Clusters > Read.

### POST /v1/cloud-providers/clusters

Creates a new cluster.
Body, required: name, provider, nodePools[].id, nodePools[].nodeType, nodePools[].nodeCount, nodePools[].diskSize.
Body, optional: description, region, kubernetesVersion, integrationId, storage, settings, restrictions, gcp, aws, oci, azure, coreweave, nebius, byok, coordinates.
Permission: Account > Cloud > Clusters > Create.

### PUT /v1/cloud-providers/clusters

Creates or update a cluster.
Body, required: name, provider, nodePools[].id, nodePools[].nodeType, nodePools[].nodeCount, nodePools[].diskSize.
Body, optional: description, region, kubernetesVersion, integrationId, storage, settings, restrictions, gcp, aws, oci, azure, coreweave, nebius, byok, coordinates.
Permission: Account > Cloud > Clusters > Create.

### GET /v1/cloud-providers/clusters/{clusterId}

Get information about the given cluster.
Permission: Account > Cloud > Clusters > Read.

### PATCH /v1/cloud-providers/clusters/{clusterId}

Updates a cluster.
Body, optional: name, description, kubernetesVersion, nodePools[], settings, restrictions, gcp, aws, azure, byok, coordinates, region.
Permission: Account > Cloud > Clusters > Update.

### DELETE /v1/cloud-providers/clusters/{clusterId}

Delete the given cluster. Fails if the cluster has associated projects.
Permission: Account > Cloud > Clusters > Delete.

### GET /v1/cloud-providers/clusters/{clusterId}/nodes

Get a list of nodes for the given cluster.
Query: per_page, page, cursor, status.
Permission: Account > Cloud > Clusters > Read.

### POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/cordon

Cordon a node on the cluster to prevent new pods from scheduling on it.
Permission: Account > Cloud > Clusters > Update.

### POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/drain

Drain a node by evicting all running pods.
Permission: Account > Cloud > Clusters > Update.

### POST /v1/cloud-providers/clusters/{clusterId}/nodes/{nodeId}/uncordon

Uncordon a node on the cluster if it was previously cordoned.
Permission: Account > Cloud > Clusters > Update.

### GET /v1/cloud-providers/integrations

Lists integrations for the authenticated user or team.
Query: per_page, page, cursor.
Permission: Account > Cloud > Integrations > Read.

### POST /v1/cloud-providers/integrations

Creates a new integration.
Body, required: name, provider, credentials.
Body, optional: description, features, restrictions, aws, gcp, cloudflare.
Permission: Account > Cloud > Integrations > Create.

### PUT /v1/cloud-providers/integrations

Creates or updates a integration.
Body, required: name, provider, credentials.
Body, optional: description, features, restrictions, aws, gcp, cloudflare.
Permission: Account > Cloud > Integrations > Create.

### GET /v1/cloud-providers/integrations/{integrationId}

Get information about the given integration.
Permission: Account > Cloud > Integrations > Read.

### PATCH /v1/cloud-providers/integrations/{integrationId}

Updates a integration.
Body, optional: description, features, restrictions, credentials, aws.
Permission: Account > Cloud > Integrations > Update.

### DELETE /v1/cloud-providers/integrations/{integrationId}

Delete the given integration. Fails if the integration is associated with existing clusters.
Permission: Account > Cloud > Integrations > Delete.

### GET /v1/cloud-providers/node-types

Lists supported cloud provider node types.
Query: per_page, page, cursor, provider, region, family, maxGenerationAge, hasGpu.
Permission: undefined.

### GET /v1/cloud-providers/regions

Lists supported cloud provider regions.
Query: per_page, page, cursor, provider.
Permission: undefined.
