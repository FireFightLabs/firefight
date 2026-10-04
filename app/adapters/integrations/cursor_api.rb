module Integrations
  # Cursor's Cloud Agents API (v1, public beta) with a user's or a service account's API key, sent as a bearer token,
  # which Cursor accepts as well as basic authentication. Paths, bodies and answers are from Cursor's reference,
  # https://cursor.com/docs/cloud-agent/api/endpoints.md, and its OpenAPI document,
  # https://cursor.com/docs-static/cloud-agents-openapi.yaml: GET /v1/me, POST /v1/agents, GET /v1/agents/{id}, GET and
  # cancel /v1/agents/{id}/runs/{runId}, and GET /v1/agents/{id}/usage.
  class CursorApi < CodingAgentApi
    NAME = "Cursor".freeze
    ROOT = "https://api.cursor.com/v1".freeze

    def me = call(:get, "/me")

    def create_agent(body) = call(:post, "/agents", body: body)

    def agent(id) = call(:get, "/agents/#{segment(id)}")

    def run(agent_id, run_id) = call(:get, "/agents/#{segment(agent_id)}/runs/#{segment(run_id)}")

    def cancel(agent_id, run_id) = call(:post, "/agents/#{segment(agent_id)}/runs/#{segment(run_id)}/cancel")

    def usage(agent_id) = call(:get, "/agents/#{segment(agent_id)}/usage")

    private

    # Errors come as { error: { code, message } }.
    def reason(body) = body.dig("error", "message").presence
  end
end
