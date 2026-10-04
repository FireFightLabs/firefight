module Integrations
  # Calls to Railway's public GraphQL API with a workspace's own account or workspace token, for the Railway
  # integration. Every query and mutation is one the Railway CLI sends (railwayapp/cli, src/gql) or Railway's API docs
  # give (railwayapp/docs, content/docs/integrations/api), checked against the schema the CLI is built from
  # (src/gql/schema.json).
  class RailwayApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error; end

    ENDPOINT = "https://backboard.railway.com/graphql/v2".freeze
    TOO_MANY_REQUESTS = 429
    PAGE_SIZE = 100
    MAX_PAGES = 10

    PROJECT = <<~GRAPHQL.freeze
      query Project($id: String!) { project(id: $id) { id name workspaceId environments { edges { node { id name } } } } }
    GRAPHQL

    # From the CLI's EnvironmentInstances query (src/gql/queries/strings/EnvironmentInstances.graphql), with the region
    # and the service's own fields the map and status read.
    INSTANCES = <<~GRAPHQL.freeze
      query EnvironmentInstances($environmentId: String!, $projectId: String!, $first: Int, $after: String) {
        environment(id: $environmentId, projectId: $projectId) {
          serviceInstances(first: $first, after: $after) {
            edges { node {
              id serviceId serviceName environmentId numReplicas region cronSchedule nextCronRunAt startCommand healthcheckPath
              healthcheckTimeout restartPolicyType restartPolicyMaxRetries sleepApplication
              source { repo image }
              latestDeployment { id status createdAt meta canRollback deploymentStopped instances { id status } }
              domains { serviceDomains { domain targetPort } customDomains { domain targetPort } }
            } }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    GRAPHQL

    DEPLOYMENTS = <<~GRAPHQL.freeze
      query Deployments($input: DeploymentListInput!, $first: Int) {
        deployments(input: $input, first: $first) {
          edges { node { id status createdAt updatedAt meta canRollback creator { name email } staticUrl } }
        }
      }
    GRAPHQL

    ENVIRONMENT_LOGS = <<~GRAPHQL.freeze
      query EnvironmentLogs($environmentId: String!, $filter: String, $beforeLimit: Int, $beforeDate: String, $anchorDate: String, $afterDate: String, $afterLimit: Int) {
        environmentLogs(environmentId: $environmentId, filter: $filter, beforeLimit: $beforeLimit, beforeDate: $beforeDate, anchorDate: $anchorDate, afterDate: $afterDate, afterLimit: $afterLimit) {
          timestamp message severity tags { deploymentInstanceId }
        }
      }
    GRAPHQL

    BUILD_LOGS = <<~GRAPHQL.freeze
      query BuildLogs($deploymentId: String!, $filter: String, $limit: Int, $startDate: DateTime, $endDate: DateTime) {
        buildLogs(deploymentId: $deploymentId, filter: $filter, limit: $limit, startDate: $startDate, endDate: $endDate) { timestamp message severity }
      }
    GRAPHQL

    HTTP_LOGS = <<~GRAPHQL.freeze
      query HttpLogs($deploymentId: String!, $filter: String, $beforeLimit: Int!, $beforeDate: String, $anchorDate: String, $afterDate: String, $afterLimit: Int) {
        httpLogs(deploymentId: $deploymentId, filter: $filter, beforeLimit: $beforeLimit, beforeDate: $beforeDate, anchorDate: $anchorDate, afterDate: $afterDate, afterLimit: $afterLimit) {
          timestamp method path host httpStatus totalDuration responseDetails deploymentInstanceId
        }
      }
    GRAPHQL

    METRICS = <<~GRAPHQL.freeze
      query Metrics($serviceId: String, $environmentId: String, $startDate: DateTime!, $endDate: DateTime, $measurements: [MetricMeasurement!]!, $sampleRateSeconds: Int) {
        metrics(serviceId: $serviceId, environmentId: $environmentId, startDate: $startDate, endDate: $endDate, measurements: $measurements, sampleRateSeconds: $sampleRateSeconds) {
          measurement values { ts value }
        }
      }
    GRAPHQL

    HTTP_BY_STATUS = <<~GRAPHQL.freeze
      query HttpMetricsByStatus($serviceId: String!, $environmentId: String!, $startDate: DateTime!, $endDate: DateTime!, $stepSeconds: Int) {
        httpMetricsGroupedByStatus(serviceId: $serviceId, environmentId: $environmentId, startDate: $startDate, endDate: $endDate, stepSeconds: $stepSeconds) {
          statusCode samples { ts value }
        }
      }
    GRAPHQL

    # Each of these answers a Boolean, so nothing is selected on it (schema, type Mutation).
    RESTART = "mutation DeploymentRestart($id: String!) { deploymentRestart(id: $id) }".freeze
    ROLLBACK = "mutation DeploymentRollback($id: String!) { deploymentRollback(id: $id) }".freeze
    PATCH_COMMIT = <<~GRAPHQL.freeze
      mutation EnvironmentPatchCommit($environmentId: String!, $patch: EnvironmentConfig!, $commitMessage: String) {
        environmentPatchCommit(environmentId: $environmentId, patch: $patch, commitMessage: $commitMessage)
      }
    GRAPHQL

    def initialize(token)
      @token = token
    end

    def project(project_id) = query(PROJECT, "id" => project_id)["project"]

    # Every service instance in an environment, up to MAX_PAGES pages.
    def service_instances(project_id, environment_id)
      rows = []
      after = nil
      MAX_PAGES.times do
        connection = query(INSTANCES, "projectId" => project_id, "environmentId" => environment_id, "first" => PAGE_SIZE, "after" => after)
                     .dig("environment", "serviceInstances") || {}
        rows.concat(Array(connection["edges"]).filter_map { |edge| edge["node"] })
        break unless connection.dig("pageInfo", "hasNextPage")

        after = connection.dig("pageInfo", "endCursor")
      end
      rows
    end

    def deployments(project_id, environment_id, service_id, limit:)
      input = { "projectId" => project_id, "environmentId" => environment_id, "serviceId" => service_id }
      Array(query(DEPLOYMENTS, "input" => input, "first" => limit).dig("deployments", "edges")).filter_map { |edge| edge["node"] }
    end

    def environment_logs(variables) = Array(query(ENVIRONMENT_LOGS, variables)["environmentLogs"])

    def build_logs(variables) = Array(query(BUILD_LOGS, variables)["buildLogs"])

    def http_logs(variables) = Array(query(HTTP_LOGS, variables)["httpLogs"])

    def metrics(variables) = Array(query(METRICS, variables)["metrics"])

    def http_by_status(variables) = Array(query(HTTP_BY_STATUS, variables)["httpMetricsGroupedByStatus"])

    def restart(deployment_id) = query(RESTART, "id" => deployment_id)["deploymentRestart"]

    def rollback(deployment_id) = query(ROLLBACK, "id" => deployment_id)["deploymentRollback"]

    def patch_commit(environment_id, patch, message) = query(PATCH_COMMIT, "environmentId" => environment_id, "patch" => patch, "commitMessage" => message)

    private

    # Railway answers a refusal with HTTP 200 and an errors list, and a 429 when asked too often (docs,
    # content/docs/integrations/api.md, Errors and Rate limits).
    def query(text, variables)
      uri = URI.parse(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json"
      request.body = { query: text, variables: variables.compact }.to_json
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      body = JSON.parse(response.body.to_s.presence || "{}")
      message = Array(body["errors"]).filter_map { |error| error["message"] }.first if body.is_a?(Hash)
      raise RateLimited, "Railway answered 429: #{message || 'too many requests'}" if response.code.to_i == TOO_MANY_REQUESTS
      raise Error, "Railway answered #{response.code}: #{message || 'no reason given'}" unless response.code.to_i.between?(200, 299)
      raise Error, "Railway refused this: #{message}" if message

      body["data"] || {}
    rescue JSON::ParserError
      raise Error, "Railway answered #{response.code} with something that is not JSON"
    end
  end
end
