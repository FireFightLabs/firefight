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

    test "a team is found by its key or its name, ignoring case, with the app's token" do
      sent = capture("data" => { "teams" => { "nodes" => [ { "id" => "team-1", "key" => "ENG" } ] } })

      assert_equal "team-1", api.team("eng")["id"]
      url, auth, body = sent.sole
      assert_equal [ "https://api.linear.app/graphql", "Bearer lin_oauth" ], [ url, auth ]
      assert_equal({ "or" => [ { "key" => { "eqIgnoreCase" => "eng" } }, { "name" => { "eqIgnoreCase" => "eng" } } ] }, body.dig("variables", "filter"))
    end

    test "a webhook is created with its url, team, resource types and secret, and deleted by its id" do
      sent = capture("data" => { "webhookCreate" => { "success" => true, "webhook" => { "id" => "wh-1", "enabled" => true } } })

      webhook = api.create_webhook("url" => "https://ff.example.com/hook", "teamId" => "team-1", "resourceTypes" => [ "Issue" ], "secret" => "s")

      assert_equal "wh-1", webhook["id"]
      assert_match "webhookCreate(input: $input)", sent.sole.last["query"]
      assert_equal "s", sent.sole.last.dig("variables", "input", "secret")
    end

    test "Linear's errors list is its refusal" do
      capture("errors" => [ { "message" => "Entity not found: Issue" } ])

      error = assert_raises(LinearApi::Error) { api.issue("ENG-1") }
      assert_equal "Linear refused this: Entity not found: Issue", error.message
    end

    test "an agent activity and a session's links are sent as agentActivityCreate and agentSessionUpdate take them" do
      sent = capture("data" => { "agentActivityCreate" => { "success" => true } })
      assert api.create_activity("agentSessionId" => "session-1", "content" => { "type" => "thought", "body" => "On it." })
      assert_match "agentActivityCreate(input: $input)", sent.sole.last["query"]
      assert_equal "thought", sent.sole.last.dig("variables", "input", "content", "type")

      sent = capture("data" => { "agentSessionUpdate" => { "success" => true } })
      api.update_session("session-1", "externalUrls" => [ { "label" => "Open in Firefight", "url" => "https://ff.example.com/app/agent/1" } ])
      assert_match "agentSessionUpdate(id: $id, input: $input)", sent.sole.last["query"]
      assert_equal "session-1", sent.sole.last.dig("variables", "id")
    end

    test "who the token acts as comes with its organization and whether it reaches a team" do
      capture("data" => { "viewer" => { "id" => "u", "app" => true, "organization" => { "id" => "org-1" } }, "teams" => { "nodes" => [ { "id" => "t" } ] } })

      assert_equal [ true, "org-1", [ { "id" => "t" } ] ], api.actor.values_at("app", "organization", "teams").then { |app, org, teams| [ app, org["id"], teams ] }
    end

    test "a token Linear no longer takes is told apart from any other refusal" do
      Http.stubs(:request).returns(stub(code: "401", body: { "errors" => [ { "message" => "Authentication required" } ] }.to_json, each_header: []))

      assert_raises(LinearApi::Unauthorized) { api.viewer }
    end

    test "revoking sends the token in the token field, and one already revoked leaves nothing to do" do
      Http.expects(:request).with { |uri, request, **| uri.to_s == "https://api.linear.app/oauth/revoke" && URI.decode_www_form(request.body).to_h["token"] == "tok" }
          .returns(stub(code: "400"))

      assert LinearApi.revoke("tok")
    end
  end
end
