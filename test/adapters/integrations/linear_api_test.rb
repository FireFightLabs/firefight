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
  end
end
