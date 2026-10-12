require "test_helper"

module Integrations
  # Requests are checked against Linear's schema (linear/linear, packages/sdk/src/schema.graphql).
  class LinearApiTest < ActiveSupport::TestCase
    def capture(answer)
      sent = []
      Http.stubs(:json).with { |uri, request, **| sent << [ uri.to_s, request["Authorization"], JSON.parse(request.body) ] }.returns(answer)
      sent
    end

    def api = LinearApi.new("Authorization" => "Bearer lin_oauth")

    test "Linear's errors list is its refusal" do
      capture("errors" => [ { "message" => "Entity not found: AgentSession" } ])

      error = assert_raises(LinearApi::Error) { api.create_activity("agentSessionId" => "gone") }
      assert_equal "Linear refused this: Entity not found: AgentSession", error.message
    end

    test "an agent activity is sent as agentActivityCreate takes it, with the app's token" do
      sent = capture("data" => { "agentActivityCreate" => { "success" => true } })
      assert api.create_activity("agentSessionId" => "session-1", "content" => { "type" => "thought", "body" => "On it." })
      url, auth, body = sent.sole
      assert_equal [ "https://api.linear.app/graphql", "Bearer lin_oauth" ], [ url, auth ]
      assert_match "agentActivityCreate(input: $input)", body["query"]
      assert_equal "thought", body.dig("variables", "input", "content", "type")
    end

    test "who the token acts as comes with its organization and whether it reaches a team" do
      capture("data" => { "viewer" => { "id" => "u", "app" => true, "organization" => { "id" => "org-1" } }, "teams" => { "nodes" => [ { "id" => "t" } ] } })

      assert_equal [ true, "org-1", [ { "id" => "t" } ] ], api.actor.values_at("app", "organization", "teams").then { |app, org, teams| [ app, org["id"], teams ] }
    end

    test "a token Linear no longer takes is told apart from any other refusal" do
      Http.stubs(:request).returns(stub(code: "401", body: { "errors" => [ { "message" => "Authentication required" } ] }.to_json, each_header: []))

      assert_raises(LinearApi::Unauthorized) { api.actor }
    end

    test "revoking sends the token in the token field, and one already revoked leaves nothing to do" do
      Http.expects(:request).with { |uri, request, **| uri.to_s == "https://api.linear.app/oauth/revoke" && URI.decode_www_form(request.body).to_h["token"] == "tok" }
          .returns(stub(code: "400"))

      assert LinearApi.revoke("tok")
    end
  end
end
