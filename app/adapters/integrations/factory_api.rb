module Integrations
  # Factory's public API with a Factory API key, for Droid sessions on a Droid Computer. Paths, bodies and answers are
  # from Factory's OpenAPI document, https://docs.factory.com/openapi.json: GET /api/v0/computers/name/{name}, POST
  # /api/v0/sessions, GET /api/v0/sessions/{id}, POST and GET /api/v0/sessions/{id}/messages and POST
  # /api/v0/sessions/{id}/interrupt. Factory says the sessions API is switched on for selected organizations only. An EU
  # organization lives on Factory's separate EU deployment, whose API is api.eu.factory.ai.
  class FactoryApi < CodingAgentApi
    NAME = "Factory".freeze
    ROOTS = { "global" => "https://api.factory.ai/api/v0", "eu" => "https://api.eu.factory.ai/api/v0" }.freeze
    # The most a page of messages holds.
    MESSAGES_PAGE = 100

    # region is the connection's region key, Global when it names none.
    def initialize(key, region = nil)
      super(key)
      @root = ROOTS.fetch(region.to_s, ROOTS.fetch("global"))
    end

    def computer_named(name) = call(:get, "/computers/name/#{segment(name)}")

    def create_session(body) = call(:post, "/sessions", body: body)

    def session(id) = call(:get, "/sessions/#{segment(id)}")

    def send_message(id, text) = call(:post, "/sessions/#{segment(id)}/messages", body: { "text" => text })

    def messages(id, cursor: nil) = call(:get, "/sessions/#{segment(id)}/messages", query: { "role" => "assistant", "limit" => MESSAGES_PAGE.to_s, "cursor" => cursor })

    def interrupt(id) = call(:post, "/sessions/#{segment(id)}/interrupt")

    private

    def root = @root
  end
end
