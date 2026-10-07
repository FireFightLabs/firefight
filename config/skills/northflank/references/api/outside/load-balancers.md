# load-balancers

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/load-balancers

Gets a list of load balancers belonging to the team.
Query: per_page, page, cursor.
Permission: Account > Networking > LoadBalancers > Read.

### POST /v1/load-balancers

Creates a new load balancer.
Body, required: name, spec.type, spec.target.type, spec.ports[].id, spec.ports[].port, spec.ports[].backends[].id, spec.ports[].backends[].type, spec.ports[].backends[].port.
Body, optional: description.
Permission: Account > Networking > LoadBalancers > Create.

### PUT /v1/load-balancers

Creates or updates a load balancer.
Body, required: name, spec.type, spec.target.type, spec.ports[].id, spec.ports[].port, spec.ports[].backends[].id, spec.ports[].backends[].type, spec.ports[].backends[].port.
Body, optional: description.
Permission: Account > Networking > LoadBalancers > Create.

### GET /v1/load-balancers/{loadBalancerId}

Gets information about the given load balancer.
Permission: Account > Networking > LoadBalancers > Read.

### PATCH /v1/load-balancers/{loadBalancerId}

Updates a load balancer.
Body, optional: name, description, spec.
Permission: Account > Networking > LoadBalancers > Update.

### DELETE /v1/load-balancers/{loadBalancerId}

Deletes the given load balancer.
Permission: Account > Networking > LoadBalancers > Delete.
