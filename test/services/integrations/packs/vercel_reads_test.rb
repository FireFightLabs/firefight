require "test_helper"

module Integrations
  module Packs
    # Vercel's general read, api_read, always in the connection's team.
    class VercelReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "vercel", name: "Vercel")
        @row = @integration.integration_environments.create!
        Vercel.store_credentials!(@row, Vercel::API_TOKEN => "tok")
        @row.store_fields!(Vercel::TEAM => %w[team_1])
        @pack = Vercel.new(@integration)
        VercelApi.any_instance.stubs(:team).with("team_1").returns("slug" => "acme")
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        assert Vercel.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        assert_equal ReadGuards::Vercel, Provider.for("vercel").read_guard
      end

      test "every request names the connection's team, whatever the query says" do
        Http.expects(:json).with do |uri, request, *|
          query = URI.decode_www_form(uri.query).to_h
          uri.path == "/v6/domains" && query == { "limit" => "5", "teamId" => "team_1" } && request.is_a?(Net::HTTP::Get)
        end.returns("domains" => [ { "name" => "shop.acme.dev" } ])

        text = text(call("path" => "/v6/domains", "query" => { "limit" => 5, "teamId" => "team_other", "slug" => "other" }))
        assert_match "Vercel answered GET /v6/domains?limit=5", text
        assert_match "shop.acme.dev", text
      end

      test "a deployment links its own page, and a project path the project's page" do
        VercelApi.any_instance.stubs(:read).with("/v13/deployments/dpl_1", {}).returns("id" => "dpl_1", "inspectorUrl" => "https://vercel.com/acme/shop/dpl1")
        assert_includes text(call("path" => "/v13/deployments/dpl_1")), "https://vercel.com/acme/shop/dpl1"

        VercelApi.any_instance.stubs(:read).with("/v9/projects/shop/domains", {}).returns("domains" => [])
        VercelApi.any_instance.stubs(:projects).returns(Integrations::Pages::Read.new(items: [ { "id" => "prj_1", "name" => "shop" } ], complete: true))
        assert_includes text(call("path" => "/v9/projects/shop/domains")), "https://vercel.com/acme/shop"
      end

      test "another team is refused, by its path or in the list of teams" do
        VercelApi.any_instance.expects(:read).with("/v2/teams/team_2/members", anything).never
        assert_match "reaches team_2", assert_raises(PolicyRefusal) { call("path" => "/v2/teams/team_2/members") }.message

        VercelApi.any_instance.stubs(:read).with("/v2/teams", {}).returns("teams" => [ { "id" => "team_1" }, { "id" => "team_2" } ])
        assert_raises(PolicyRefusal) { call("path" => "/v2/teams") }
      end

      test "a project's protection bypass and environment values never come back, and decrypt is never sent" do
        VercelApi.any_instance.stubs(:read).with("/v9/projects/shop", {}).returns(
          "id" => "prj_1", "name" => "shop", "protectionBypass" => { "bypass-secret-123" => { "scope" => "automation-bypass" } },
          "env" => [ { "key" => "STRIPE_KEY", "value" => "sk_live_abc" } ]
        )
        shown = text(call("path" => "/v9/projects/shop"))
        %w[bypass-secret-123 sk_live_abc].each { |secret| assert_not_includes shown, secret }
        assert_includes shown, "STRIPE_KEY"

        VercelApi.any_instance.expects(:read).with("/v10/projects/shop/env", anything).never
        assert_raises(PolicyRefusal) { call("path" => "/v10/projects/shop/env", "query" => { "decrypt" => true }) }
      end

      test "a deploy hook's address is a credential wherever it appears in an answer" do
        said = { "content" => [ { "type" => "text", "text" => "url: https://api.vercel.com/v1/integrations/deploy/prj_1/abcDEF123" } ] }

        shown = Redactions.apply(said, **Redactions.rules("vercel"))["content"].sole["text"]
        assert_equal "url: https://[REDACTED:vercel_deploy_hook]", shown
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
