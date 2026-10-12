module Integrations
  # Calls to Linear's GraphQL API (https://api.linear.app/graphql) with the token of Firefight's own Linear OAuth
  # application, for what the app does beside the tools of Linear's MCP server: who the token acts as, and for the app's
  # agent sessions agentActivityCreate (linear.app/developers/agent-interaction). Each query is written against the schema
  # Linear's SDK is generated from (linear/linear, packages/sdk/src/schema.graphql). Linear answers a refusal with an
  # errors list (linear.app/developers/graphql, Errors), and a token it no longer takes with 401
  # (linear.app/developers/oauth-2-0-authentication).
  class LinearApi
    class Error < Integrations::Error; end
    class Unauthorized < Error; end

    ENDPOINT = "https://api.linear.app/graphql".freeze
    PROVIDER = "Linear".freeze
    REASON = ->(body) { Array(body["errors"]).filter_map { |error| error["message"] if error.is_a?(Hash) }.first }

    # Who the token acts as, and the workspace it was installed in. A token authorized with actor=app acts as the app's
    # own user, whose app is true (User.app in the schema).
    ACTOR = "query Actor { viewer { id app organization { id name urlKey } } teams(first: 1) { nodes { id } } }".freeze
    ACTIVITY_CREATE = "mutation AgentActivityCreate($input: AgentActivityCreateInput!) { agentActivityCreate(input: $input) { success } }".freeze
    UNAUTHORIZED = 401

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

    # The viewer with whether it is an app and its organization, and whether the token reaches any team at all.
    def actor
      data = query(ACTOR, {})
      data["viewer"]&.merge("teams" => Array(data.dig("teams", "nodes")))
    end

    def create_activity(input) = query(ACTIVITY_CREATE, "input" => input).dig("agentActivityCreate", "success")

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
