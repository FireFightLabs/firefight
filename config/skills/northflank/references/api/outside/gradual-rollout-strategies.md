# gradual-rollout-strategies

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/gradual-rollout-strategies

Lists the gradual rollout strategies belonging to the team, newest first.
Query: per_page, page, cursor.
Permission: Account > Platform > GradualRollouts > Read.

### POST /v1/gradual-rollout-strategies

Creates a new gradual rollout strategy.
Body, required: type, details.canaryStrategy, details.config {canaryPercentage, stablePercentage} or {canaryHeader.headerName, canaryHeader.headerValue, stableHeader.headerName, stableHeader.headerValue}.
Body, optional: name, options.
Permission: Account > Platform > GradualRollouts > Create.

### PUT /v1/gradual-rollout-strategies

Creates or updates a gradual rollout strategy.
Body, required: type, details.canaryStrategy, details.config {canaryPercentage, stablePercentage} or {canaryHeader.headerName, canaryHeader.headerValue, stableHeader.headerName, stableHeader.headerValue}.
Body, optional: name, options.
Permission: Account > Platform > GradualRollouts > Create.

### GET /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}

Gets details of the given gradual rollout strategy.
Permission: Account > Platform > GradualRollouts > Read.

### PATCH /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}

Updates a gradual rollout strategy.
Body, required: details.canaryStrategy, details.config {canaryPercentage, stablePercentage} or {canaryHeader.headerName, canaryHeader.headerValue, stableHeader.headerName, stableHeader.headerValue}.
Body, optional: name, type, options.
Permission: Account > Platform > GradualRollouts > Update.

### DELETE /v1/gradual-rollout-strategies/{gradualRolloutStrategyId}

Deletes a gradual rollout strategy. Any services still using it are detached first, which redeploys them without the rollout. Because that redeploys services, this also requires service update permission. Fails if a rollout is in progress on any of those services.
Permission: Account > Platform > GradualRollouts > Delete.
