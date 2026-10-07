module Integrations
  # Calls to Railway's public GraphQL API with a workspace's own account or workspace token, for the Railway
  # integration. Every query and mutation is one the Railway CLI sends (railwayapp/cli, src/gql) or Railway's API docs
  # give (railwayapp/docs, content/docs/integrations/api), checked against the schema the CLI is built from
  # (src/gql/schema.json).
  class RailwayApi
    class Error < Integrations::Error; end
    # Railway answered that what was asked for is not there, the one answer a re-read takes as gone. Railway words it in
    # its errors list, such as "Project not found" or "ServiceInstance not found", with HTTP 200.
    class NotFound < Error
      include Integrations::NotFound
    end
    # Railway turned the request down as it stands, such as a token without the right to change the project's webhooks
    # ("Not Authorized"), as opposed to a token it does not accept at all.
    class Refused < Error; end
    NOT_FOUND = /not found/i
    REFUSED = /not authori[sz]ed|forbidden|permission|limit|plan/i

    ENDPOINT = "https://backboard.railway.com/graphql/v2".freeze
    PROVIDER = "Railway".freeze
    # Railway puts its reason in a GraphQL errors list, with HTTP 200 for a refusal (docs, content/docs/integrations/api.md).
    REASON = ->(body) { Array(body["errors"]).filter_map { |error| error["message"] if error.is_a?(Hash) }.first }
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

    # One service instance, with the fields INSTANCES reads for each (schema, Query.serviceInstance).
    INSTANCE = <<~GRAPHQL.freeze
      query ServiceInstance($environmentId: String!, $serviceId: String!) {
        serviceInstance(environmentId: $environmentId, serviceId: $serviceId) {
          id serviceId serviceName environmentId numReplicas region cronSchedule nextCronRunAt startCommand healthcheckPath
          healthcheckTimeout restartPolicyType restartPolicyMaxRetries sleepApplication
          source { repo image }
          latestDeployment { id status createdAt meta canRollback deploymentStopped instances { id status } }
          domains { serviceDomains { domain targetPort } customDomains { domain targetPort } }
        }
      }
    GRAPHQL

    # A project's webhooks are its notification rules, each with channels whose config is { type: "webhook", url, headers },
    # header values never answered (schema, Query.notificationRules and NotificationRule, and the documents Railway's own
    # dashboard sends, NotificationRuleFields). Railway's docs say the same of headers (docs,
    # content/docs/observability/webhooks.md, Custom headers).
    NOTIFICATION_RULE_FIELDS = "id projectId eventTypes ephemeralEnvironments channels { id config }".freeze
    NOTIFICATION_RULES = <<~GRAPHQL.freeze
      query NotificationRules($workspaceId: String!, $projectId: String!) {
        notificationRules(workspaceId: $workspaceId, projectId: $projectId) { #{NOTIFICATION_RULE_FIELDS} }
      }
    GRAPHQL
    NOTIFICATION_RULE_CREATE = <<~GRAPHQL.freeze
      mutation NotificationRuleCreate($input: CreateNotificationRuleInput!) { notificationRuleCreate(input: $input) { #{NOTIFICATION_RULE_FIELDS} } }
    GRAPHQL
    NOTIFICATION_RULE_UPDATE = <<~GRAPHQL.freeze
      mutation NotificationRuleUpdate($id: String!, $input: UpdateNotificationRuleInput!) {
        notificationRuleUpdate(id: $id, input: $input) { #{NOTIFICATION_RULE_FIELDS} }
      }
    GRAPHQL
    NOTIFICATION_RULE_DELETE = "mutation NotificationRuleDelete($id: String!) { notificationRuleDelete(id: $id) }".freeze
    WEBHOOK_CHANNEL = "webhook".freeze

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

    # A service's variables twice, as the CLI reads them to edit them (src/gql/queries/strings/ServiceVariablesForEdit.graphql):
    # as set, with unrendered, where a reference to another service stays as written (${{Postgres.DATABASE_URL}}), and
    # rendered, as the deployment gets them (variablesForServiceDeployment, schema "All rendered variables that are
    # required for a service deployment"). Each is a map of name to value, a sealed variable's value null
    # (src/controllers/variables.rs). Values are read only in memory.
    SERVICE_VARIABLES = <<~GRAPHQL.freeze
      query ServiceVariables($projectId: String!, $environmentId: String!, $serviceId: String!) {
        unrendered: variables(projectId: $projectId, environmentId: $environmentId, serviceId: $serviceId, unrendered: true)
        rendered: variablesForServiceDeployment(projectId: $projectId, environmentId: $environmentId, serviceId: $serviceId)
      }
    GRAPHQL

    def initialize(token)
      @token = token
    end

    def project(project_id) = query(PROJECT, "id" => project_id)["project"]

    # Every service instance in an environment, as a Pages::Read that says whether it was read to its end.
    def service_instances(project_id, environment_id)
      Pages.read(max_pages: MAX_PAGES) do |after|
        connection = query(INSTANCES, "projectId" => project_id, "environmentId" => environment_id, "first" => PAGE_SIZE, "after" => after)
                     .dig("environment", "serviceInstances") || {}
        nodes = Array(connection["edges"]).filter_map { |edge| edge["node"] }
        [ nodes, (connection.dig("pageInfo", "endCursor") if connection.dig("pageInfo", "hasNextPage")) ]
      end
    end

    def service_instance(environment_id, service_id) = query(INSTANCE, "environmentId" => environment_id, "serviceId" => service_id)["serviceInstance"]

    # The project's webhooks, read only to find one Firefight registered before at the same address.
    def notification_rules(workspace_id, project_id) = Array(query(NOTIFICATION_RULES, "workspaceId" => workspace_id, "projectId" => project_id)["notificationRules"])

    # A webhook for the event types named, in the project's own environments only (ephemeralEnvironments false leaves out
    # preview environments, as the dashboard's form does), sending headers with every delivery.
    def create_webhook(workspace_id, project_id, url:, events:, headers:)
      input = { "workspaceId" => workspace_id, "projectId" => project_id, "eventTypes" => events, "ephemeralEnvironments" => false,
                "channelConfigs" => [ webhook_channel(url, headers) ] }
      query(NOTIFICATION_RULE_CREATE, "input" => input)["notificationRuleCreate"]
    end

    # Sets a webhook's event types and headers again, replacing every header it had (docs, Custom headers).
    def update_webhook(rule_id, url:, events:, headers:)
      input = { "eventTypes" => events, "ephemeralEnvironments" => false, "channelConfigs" => [ webhook_channel(url, headers) ] }
      query(NOTIFICATION_RULE_UPDATE, "id" => rule_id, "input" => input)["notificationRuleUpdate"]
    end

    def delete_webhook(rule_id) = query(NOTIFICATION_RULE_DELETE, "id" => rule_id)["notificationRuleDelete"]

    def service_variables(project_id, environment_id, service_id)
      answer = query(SERVICE_VARIABLES, "projectId" => project_id, "environmentId" => environment_id, "serviceId" => service_id)
      [ answer["unrendered"].to_h, answer["rendered"].to_h ]
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

    def webhook_channel(url, headers) = { "type" => WEBHOOK_CHANNEL, "url" => url, "headers" => headers }

    # Railway answers a refusal with HTTP 200 and an errors list, and a 429 when asked too often (docs,
    # content/docs/integrations/api.md, Errors and Rate limits).
    def query(text, variables)
      uri = URI.parse(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Content-Type"] = "application/json"
      request.body = { query: text, variables: variables.compact }.to_json
      body = Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON)
      message = REASON.call(body) if body.is_a?(Hash)
      raise error_for(message), "Railway refused this: #{message}" if message

      body.is_a?(Hash) ? body["data"] || {} : {}
    end

    def error_for(message)
      return NotFound if message.match?(NOT_FOUND)

      message.match?(REFUSED) ? Refused : Error
    end
  end
end
