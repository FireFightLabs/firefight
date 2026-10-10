require "test_helper"

module Integrations
  module Packs
    # Netlify's general read, api_read, reaching what the connection's token reaches.
    class NetlifyReadsTest < ActiveSupport::TestCase
      ADMIN = "https://app.netlify.com/projects/shop".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: Netlify::PROVIDER_KEY, name: "Netlify")
        @row = @integration.integration_environments.create!
        Netlify.store_credentials!(@row, Netlify::API_TOKEN => "nfp_x")
        @pack = Netlify.new(@integration)
        NetlifyApi.any_instance.stubs(:sites).returns(Integrations::Pages::Read.new(items: [ { "id" => "site-1", "name" => "shop", "admin_url" => ADMIN } ], complete: true))
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        assert Netlify.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        assert_equal ReadGuards::Netlify, Provider.for(Netlify::PROVIDER_KEY).read_guard
      end

      test "a read inside a site answers with the site's page, and its query goes as parameters" do
        NetlifyApi.any_instance.expects(:read).with("/sites/site-1/forms", { "per_page" => "20" }).returns([ { "id" => "f1", "name" => "contact" } ])

        shown = text(call("path" => "sites/site-1/forms", "query" => { "per_page" => 20 }))
        assert_match "Netlify answered GET /sites/site-1/forms?per_page=20.", shown
        assert_includes shown, "contact"
        assert_includes shown, ADMIN
      end

      test "a site's password and build environment, and an account's variables, never come back" do
        NetlifyApi.any_instance.stubs(:read).with("/sites/site-1", {}).returns(
          "id" => "site-1", "admin_url" => ADMIN, "password" => "hunter2", "build_settings" => { "env" => { "STRIPE_KEY" => "sk_live_abc" } }
        )
        NetlifyApi.any_instance.stubs(:read).with("/accounts/acc-1/env", {}).returns([ { "key" => "DB_URL", "values" => [ { "value" => "postgres://u:p@h/db", "context" => "all" } ] } ])

        site = text(call("path" => "/sites/site-1"))
        %w[hunter2 sk_live_abc].each { |secret| assert_not_includes site, secret }
        assert_includes site, "STRIPE_KEY"
        env = text(call("path" => "/accounts/acc-1/env"))
        assert_includes env, "DB_URL"
        assert_not_includes env, "u:p@h"
      end

      test "a build hook's address is a credential wherever it appears in an answer" do
        said = { "content" => [ { "type" => "text", "text" => "url https://api.netlify.com/build_hooks/5c23354f454e1350f8543e78" } ] }

        assert_equal "url https://[REDACTED:netlify_build_hook]", Redactions.apply(said, **Redactions.rules("netlify"))["content"].sole["text"]
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
