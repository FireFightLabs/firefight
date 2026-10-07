# domains

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/domains

Lists available domains.
Query: per_page, page, cursor.
Permission: Account > Networking > Domains > Read.

### POST /v1/domains

Registers a new domain.
Body, required: domain.
Body, optional: redirect, loadBalancer, options, certificates.
Permission: Account > Networking > Domains > Create.

### GET /v1/domains/{domain}

Gets details about domain.
Permission: Account > Networking > Domains > Read.

### PATCH /v1/domains/{domain}

Update domain options such as minimum TLS protocol version.
Body, required: options.
Permission: Account > Networking > Domains > Update.

### DELETE /v1/domains/{domain}

Deletes a domain and each of its registered subdomains.
Permission: Account > Networking > Domains > Delete.

### GET /v1/domains/{domain}/certificate

Retrieve certificate data for a domain to verify its contents.
Permission: Account > Networking > Domains > Read.

### POST /v1/domains/{domain}/import

Import a certificate for the domain.
Body, required: certificate.privateKey, certificate.certificateChain.
Permission: Account > Networking > Domains > Update.

### POST /v1/domains/{domain}/subdomains

Adds a new subdomain to the domain.
Body, required: subdomain.
Body, optional: routingMode, cdn, options.
Permission: Account > Networking > Subdomains > Update.

### PUT /v1/domains/{domain}/subdomains

Updates subdomain to the domain.
Body, required: name.
Body, optional: loadBalancer, certificateValidationMethod, certificate, options, cdn.
Permission: Account > Networking > Subdomains > Update.

### GET /v1/domains/{domain}/subdomains/{subdomain}

Gets details about the given subdomain.
Permission: Account > Networking > Subdomains > Read.

### DELETE /v1/domains/{domain}/subdomains/{subdomain}

Removes a subdomain from a domain.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/assign

Assigns a service port to the given subdomain.
Body, required: serviceId, projectId, portName.
Permission: Account > Networking > Subdomains > Update.

### DELETE /v1/domains/{domain}/subdomains/{subdomain}/assign

Removes a subdomain from its assigned service.
Query: unassignPaths.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/disable

Removes the CDN integration from the given subdomain.
Body, required: provider.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/enable

Enables a CDN integration on the given subdomain.
Body, required: provider.
Body, optional: options.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/cdn/purge

Purges the CDN cache for the given subdomain.
Body, required: provider.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/certificate/import

Import a certificate for a subdomain of a domain using individual certificates.
Body, required: certificate.privateKey, certificate.certificateChain.
Permission: Account > Networking > Subdomains > Update.

### PATCH /v1/domains/{domain}/subdomains/{subdomain}/geo-routing

Updates the geo routing configuration for a geo-routed subdomain.
Body, required: geoRouting.
Permission: Account > Networking > Subdomains > Update.

### GET /v1/domains/{domain}/subdomains/{subdomain}/paths

List paths for a given subdomain.
Permission: Account > Networking > SubdomainPaths > Read.

### POST /v1/domains/{domain}/subdomains/{subdomain}/paths

Adds a new path to the subdomain.
Body, required: mode, uri.
Body, optional: options.
Permission: Account > Networking > SubdomainPaths > Create.

### GET /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}

Get subdomain path details.
Permission: Account > Networking > SubdomainPaths > Read.

### POST /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}

Update a subdomain path.
Body, optional: options.
Permission: Account > Networking > SubdomainPaths > Update.

### DELETE /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}

Delete a path.
Permission: Account > Networking > SubdomainPaths > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}/assign

Assign a subdomain path to a port.
Body, required: assignment.project, assignment.service, assignment.port.
Permission: Account > Networking > SubdomainPaths > Update.

### DELETE /v1/domains/{domain}/subdomains/{subdomain}/paths/{subdomainPath}/assign

Unassign a subdomain path to a port.
Permission: Account > Networking > SubdomainPaths > Update.

### POST /v1/domains/{domain}/subdomains/{subdomain}/verify

Gets details about the given subdomain.
Permission: Account > Networking > Subdomains > Update.

### POST /v1/domains/{domain}/verify

Attempts to verify the domain.
Permission: Account > Networking > Domains > Create.
