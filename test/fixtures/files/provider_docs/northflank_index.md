# API endpoints

Every endpoint in the provider's API, as its own API client (@northflank/js-client 0.11.0) defines them, with the method and path. An operation that is not listed here is not in the API, so it cannot be done through it.

Paths inside /v1/projects/{projectId}/ are written after it. The rest are written in full. Each area's file, named under it, gives each endpoint's purpose, the body fields it requires and takes, its query options and the permission it needs.

## Paths written after /v1/projects/{projectId}/


### pipelines (project/pipelines.md)

- GET pipelines
- GET pipelines/{pipelineId}
- GET pipelines/{pipelineId}/preview-envs
- POST pipelines/{pipelineId}/preview-envs
- GET pipelines/{pipelineId}/preview-envs/previews
- DELETE pipelines/{pipelineId}/preview-envs/previews/{previewId}
- GET pipelines/{pipelineId}/preview-envs/runs
- POST pipelines/{pipelineId}/preview-envs/runs
- GET pipelines/{pipelineId}/preview-envs/runs/{templateRunId}
- GET pipelines/{pipelineId}/release-flows/{stage}
- POST pipelines/{pipelineId}/release-flows/{stage}
- GET pipelines/{pipelineId}/release-flows/{stage}/runs
- POST pipelines/{pipelineId}/release-flows/{stage}/runs
- GET pipelines/{pipelineId}/release-flows/{stage}/runs/{runId}
- POST pipelines/{pipelineId}/release-flows/{stage}/runs/{runId}/abort

