module Integrations
  # Calls to Linear's GraphQL API (https://api.linear.app/graphql) with the token of Firefight's own Linear OAuth
  # application, for keeping incident items in step with issues. Every query and mutation is written against the schema
  # Linear's SDK is generated from (linear/linear, packages/sdk/src/schema.graphql): issue, issueCreate, issueUpdate,
  # teams, workflowStates, users, webhookCreate and webhookDelete, and for the app's agent sessions agentActivityCreate
  # (linear.app/developers/agent-interaction). Linear answers a refusal with an errors list
  # (linear.app/developers/graphql, Errors), and a token it no longer takes with 401 (linear.app/developers/oauth-2-0-authentication).
  class LinearApi
    class Error < Integrations::Error; end
    class Unauthorized < Error; end

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
    # Who the token acts as, and the workspace it was installed in. A token authorized with actor=app acts as the app's
    # own user, whose app is true (User.app in the schema).
    ACTOR = "query Actor { viewer { id app organization { id name urlKey } } teams(first: 1) { nodes { id } } }".freeze
    ACTIVITY_CREATE = "mutation AgentActivityCreate($input: AgentActivityCreateInput!) { agentActivityCreate(input: $input) { success } }".freeze
    UNAUTHORIZED = 401
    WEBHOOK_DELETE = "mutation WebhookDelete($id: String!) { webhookDelete(id: $id) { success } }".freeze

    REVOKE = "https://api.linear.app/oauth/revoke".freeze

    # Revokes a token in the token form field (linear.app/developers/oauth-2-0-authentication, Revoke an access token).
    # Linear answers 400 for one already revoked, which leaves nothing to do.
    def self.revoke(token)
      uri = URI.parse(REVOKE)
      request = Net::HTTP::Post.new(uri)
      request.set_form_data("token" => token.to_s, "token_type_hint" => "access_token")
      response = Http.request(uri, request, error_class: Error)
      return true if response.code.to_i.between?(200, 299) || response.code.to_i == 400

      raise Error, "Linear answered #{response.code} when asked to remove Firefight's app."
    end

    def initialize(headers)
      @headers = headers
    end

    # Who the token is for, which answers only while it works.
    def viewer = query(VIEWER, {})["viewer"]

    # The viewer with whether it is an app and its organization, and whether the token reaches any team at all.
    def actor
      data = query(ACTOR, {})
      data["viewer"]&.merge("teams" => Array(data.dig("teams", "nodes")))
    end

    def create_activity(input) = query(ACTIVITY_CREATE, "input" => input).dig("agentActivityCreate", "success")

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
      body = Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON,
                                     refine: ->(code, _said) { Unauthorized if code == UNAUTHORIZED })
      message = REASON.call(body) if body.is_a?(Hash)
      raise Error, "Linear refused this: #{message}" if message

      body.is_a?(Hash) ? body["data"] || {} : {}
    end
  end
end
