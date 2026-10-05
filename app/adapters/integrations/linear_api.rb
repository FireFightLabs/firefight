module Integrations
  # Calls to Linear's GraphQL API (https://api.linear.app/graphql) with the token of Firefight's own Linear OAuth
  # application, for keeping incident items in step with issues. Every query and mutation is written against the schema
  # Linear's SDK is generated from (linear/linear, packages/sdk/src/schema.graphql): issue, issueCreate, issueUpdate,
  # teams, workflowStates, users, webhookCreate and webhookDelete. Linear answers a refusal with an errors list
  # (linear.app/developers/graphql, Errors).
  class LinearApi
    class Error < Integrations::Error; end

    ENDPOINT = "https://api.linear.app/graphql".freeze
    PROVIDER = "Linear".freeze
    REASON = ->(body) { Array(body["errors"]).filter_map { |error| error["message"] if error.is_a?(Hash) }.first }

    ISSUE_FIELDS = "id identifier title url updatedAt state { id name type } assignee { id name email } team { id key }".freeze

    ISSUE = "query Issue($id: String!) { issue(id: $id) { #{ISSUE_FIELDS} } }".freeze
    CREATE = "mutation IssueCreate($input: IssueCreateInput!) { issueCreate(input: $input) { success issue { #{ISSUE_FIELDS} } } }".freeze
    UPDATE = "mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) { issueUpdate(id: $id, input: $input) { success issue { #{ISSUE_FIELDS} } } }".freeze
    TEAMS = "query Teams($filter: TeamFilter) { teams(filter: $filter, first: 50) { nodes { id key name } } }".freeze
    STATES = "query States($filter: WorkflowStateFilter) { workflowStates(filter: $filter, first: 100) { nodes { id name type position } } }".freeze
    USERS = "query Users($filter: UserFilter) { users(filter: $filter, first: 20) { nodes { id name email } } }".freeze
    WEBHOOK_CREATE = "mutation WebhookCreate($input: WebhookCreateInput!) { webhookCreate(input: $input) { success webhook { id enabled } } }".freeze
    VIEWER = "query Viewer { viewer { id } }".freeze
    WEBHOOK_DELETE = "mutation WebhookDelete($id: String!) { webhookDelete(id: $id) { success } }".freeze

    def initialize(headers)
      @headers = headers
    end

    # Who the token is for, which answers only while it works.
    def viewer = query(VIEWER, {})["viewer"]

    # Linear's issue query takes an issue's id or its identifier, such as ENG-12.
    def issue(id) = query(ISSUE, "id" => id)["issue"]

    def create_issue(input) = query(CREATE, "input" => input).dig("issueCreate", "issue")

    def update_issue(id, input) = query(UPDATE, "id" => id, "input" => input).dig("issueUpdate", "issue")

    # The team a key or a name names.
    def team(key_or_name)
      filter = { "or" => [ { "key" => { "eqIgnoreCase" => key_or_name } }, { "name" => { "eqIgnoreCase" => key_or_name } } ] }
      Array(query(TEAMS, "filter" => filter).dig("teams", "nodes")).first
    end

    def states(team_id) = Array(query(STATES, "filter" => { "team" => { "id" => { "eq" => team_id } } }).dig("workflowStates", "nodes"))

    def users_by_email(email) = Array(query(USERS, "filter" => { "email" => { "eqIgnoreCase" => email } }).dig("users", "nodes"))

    def create_webhook(input) = query(WEBHOOK_CREATE, "input" => input).dig("webhookCreate", "webhook")

    def delete_webhook(id) = query(WEBHOOK_DELETE, "id" => id).dig("webhookDelete", "success")

    private

    def query(text, variables)
      uri = URI.parse(ENDPOINT)
      request = Net::HTTP::Post.new(uri)
      @headers.each { |name, value| request[name] = value }
      request["Content-Type"] = "application/json"
      request.body = { query: text, variables: variables }.to_json
      body = Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON)
      message = REASON.call(body) if body.is_a?(Hash)
      raise Error, "Linear refused this: #{message}" if message

      body.is_a?(Hash) ? body["data"] || {} : {}
    end
  end
end
