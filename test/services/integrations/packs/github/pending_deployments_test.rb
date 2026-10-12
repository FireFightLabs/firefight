require "test_helper"

module Integrations
  module Packs
    class Github
      class PendingDeploymentsTest < ActiveSupport::TestCase
        PATH = "/repos/acme/web/actions/runs/77/pending_deployments".freeze

        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a run's waiting deployments are listed with who may review them" do
          GithubApp.expects(:get).with(PATH, token: "ghs_token").returns([ waiting(can_approve: false) ])

          text = text_of(@pack.pending_deployments(environment_row: @row, arguments: { "repo" => "acme/web", "run_id" => 77 }))

          assert_includes text, "Run 77 in acme/web is waiting on:\n  production  id 5  wait timer 10 minutes from 2026-10-12T09:00:00Z  " \
                                "reviewers: ada and the sre team  Firefight may review: no"
          assert text.end_with?("https://github.com/acme/web/actions/runs/77")
        end

        test "a waiting deployment is approved with a comment when the App is a required reviewer" do
          GithubApp.stubs(:get).with(PATH, token: "ghs_token").returns([ waiting(can_approve: true) ])
          GithubApp.expects(:write).with(:post, PATH, { environment_ids: [ 5 ], state: "approved", comment: "Checked the canary" }, token: "ghs_token").returns([])

          text = text_of(@pack.review_pending_deployment(environment_row: @row, arguments: {
                                                           "repo" => "acme/web", "run_id" => 77, "environment" => "Production", "decision" => "approve", "comment" => "Checked the canary"
                                                         }))

          assert text.start_with?("Approved the deployment of run 77 in acme/web to production.")
        end

        test "a review is refused before it is sent when the App may not give it, or the run is not waiting on that environment" do
          GithubApp.stubs(:get).with(PATH, token: "ghs_token").returns([ waiting(can_approve: false) ])
          GithubApp.expects(:write).never
          arguments = { "repo" => "acme/web", "run_id" => 77, "environment" => "production", "decision" => "reject", "comment" => "Not now" }

          error = assert_raises(PolicyRefusal) { @pack.review_pending_deployment(environment_row: @row, arguments: arguments) }
          assert_equal "Firefight's GitHub App is not a required reviewer of production, so GitHub takes a review only from ada and the sre team. " \
                       "They review it on the run's page.", error.message

          error = assert_raises(PolicyRefusal) { @pack.review_pending_deployment(environment_row: @row, arguments: arguments.merge("environment" => "staging")) }
          assert_equal "Run 77 in acme/web is not waiting on staging, only on production.", error.message

          assert_match "comment is required", assert_raises(NativePack::Error) { @pack.review_pending_deployment(environment_row: @row, arguments: arguments.except("comment")) }.message
        end

        test "listing is a read and reviewing a change that needs Deployments write" do
          tools = Github.tool_definitions.index_by(&:name)
          assert tools.fetch("pending_deployments").read_only
          assert_not tools.fetch("review_pending_deployment").read_only
          assert_equal({ "actions" => Github::READ, "deployments" => Github::WRITE }, Github::NEEDS.fetch("review_pending_deployment"))
        end

        private

        def waiting(can_approve:)
          { "environment" => { "id" => 5, "name" => "production" }, "wait_timer" => 10, "wait_timer_started_at" => "2026-10-12T09:00:00Z",
            "current_user_can_approve" => can_approve,
            "reviewers" => [ { "type" => "User", "reviewer" => { "login" => "ada" } }, { "type" => "Team", "reviewer" => { "slug" => "sre" } } ] }
        end

        def text_of(result) = result.is_a?(Hash) ? result["content"].map { |part| part["text"] }.join("\n") : result
      end
    end
  end
end
