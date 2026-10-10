require "test_helper"

module Integrations
  module Packs
    class Github
      class BillingTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "an organization's billing usage is read a month at a time and added up by day, product and repository" do
          GithubApp.stubs(:installation).returns("account" => { "login" => "acme", "type" => "Organization" })
          travel_to Time.utc(2026, 10, 10, 12) do
            GithubApp.expects(:get).with("/organizations/acme/settings/billing/usage?month=9&year=2026", token: "ghs_token").returns(
              "usageItems" => [ item("2026-09-05", 9.0, "web"), item("2026-09-20", 2.0, "web") ]
            )
            GithubApp.expects(:get).with("/organizations/acme/settings/billing/usage?month=10&year=2026", token: "ghs_token").returns(
              "usageItems" => [ item("2026-10-09", 1.5, "api") ]
            )

            text = @pack.billing_usage(environment_row: @row, arguments: {})["content"].map { |part| part["text"] }.join("\n")

            assert_match "- 2026-10-09: 1.50, actions linux 1.50\n- 2026-09-20: 2.00", text
            assert_no_match "2026-09-05", text
            assert_match "By project over the whole range:\n- web: 2.00\n- api: 1.50", text
          end
        end

        test "a personal account's installation is told it has no organization's billing, and the tool needs Organization administration" do
          GithubApp.stubs(:installation).returns("account" => { "login" => "octocat", "type" => "User" })

          refused = assert_raises(NativePack::Error) { @pack.billing_usage(environment_row: @row, arguments: {}) }

          assert_match "personal account", refused.message
          assert_equal "Firefight's GitHub App needs Organization administration read on this installation for that.", Github.needs_sentence("billing_usage")
        end

        private

        def item(date, amount, repository)
          { "date" => "#{date}T00:00:00Z", "product" => "actions", "sku" => "linux", "netAmount" => amount, "repositoryName" => repository }
        end
      end
    end
  end
end
