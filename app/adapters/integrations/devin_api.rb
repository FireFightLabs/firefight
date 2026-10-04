module Integrations
  # Devin's v3 API for one organization, with a service user's key or a personal access token (both start cog_).
  # Paths, bodies and answers are from Devin's OpenAPI document, https://docs.devin.ai/v3-openapi.yaml: GET /v3/self,
  # and under /v3/organizations/{org_id}/sessions, create (SessionCreateRequest), get (SessionResponse), the messages
  # (PaginatedResponse[SessionMessage], oldest first) and terminate (DELETE).
  class DevinApi < CodingAgentApi
    NAME = "Devin".freeze
    ROOT = "https://api.devin.ai/v3".freeze
    # The most a page of messages holds.
    MESSAGES_PAGE = 200

    def initialize(key, organization)
      super(key)
      @organization = organization
    end

    # Who the key acts as: a service user with its organization, or a person.
    def whoami = call(:get, "/self")

    def create_session(body) = call(:post, sessions_path, body: body)

    def session(id) = call(:get, "#{sessions_path}/#{segment(id)}")

    def messages(id, after: nil) = call(:get, "#{sessions_path}/#{segment(id)}/messages", query: { "first" => MESSAGES_PAGE, "after" => after })

    def terminate(id) = call(:delete, "#{sessions_path}/#{segment(id)}")

    private

    def sessions_path = "/organizations/#{segment(@organization)}/sessions"

    # Errors come as RFC 9457 problem details, whose detail says what went wrong.
    def reason(body) = body["detail"].presence&.to_s || body["title"].presence
  end
end
