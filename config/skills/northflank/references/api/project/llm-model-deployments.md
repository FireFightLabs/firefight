# llm-model-deployments

Paths written after /v1/projects/{projectId}/. Every endpoint here is from @northflank/js-client 0.11.0.

### GET llm-model-deployments

Lists all AI models for a project.
Query: per_page, page, cursor.
Permission: Project > AiModels > General > Read.

### POST llm-model-deployments

Create an AI model.
Body, required: name, spec.type, spec.configuration.
Body, optional: description, tags, ports[].
Permission: Project > AiModels > General > Create.

### GET llm-model-deployments/{llmModelDeploymentId}

Gets details about an AI model.
Permission: Project > AiModels > General > Read.

### POST llm-model-deployments/{llmModelDeploymentId}

Updates an AI model.
Body, optional: name, description, tags, ports[], spec.
Permission: Project > AiModels > General > Update.

### DELETE llm-model-deployments/{llmModelDeploymentId}

Delete an AI model.
Permission: Project > AiModels > General > Delete.
