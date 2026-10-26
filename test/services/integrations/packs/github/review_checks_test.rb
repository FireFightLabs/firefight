require "test_helper"

module Integrations
  module Packs
    class Github
      class ReviewChecksTest < ActiveSupport::TestCase
        setup do
          @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration)
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "the review's check is a commit status under its own name, its words cut to what GitHub keeps" do
          check = ReviewChecks::Check.new(state: ReviewChecks::FAILING, description: "x" * 200, url: "https://firefight.test/app/memory")
          GithubApp.expects(:write).with(:post, "/repos/acme/web/statuses/#{'a' * 40}",
                                         { state: "failure", context: ReviewChecks::NAME, description: "#{'x' * 137}...", target_url: "https://firefight.test/app/memory" },
                                         token: "ghs_token").returns({})

          assert ReviewChecks.sets?(@integration)
          ReviewChecks.set!(@row, repository: "acme/web", sha: "a" * 40, check: check)
        end

        test "an App without the commit status permission is refused in words saying what to accept" do
          GithubApp.stubs(:write).raises(GithubApp::NotPermitted, "Resource not accessible by integration")
          check = ReviewChecks::Check.new(state: ReviewChecks::PASSING, description: "Fine.", url: nil)

          error = assert_raises(Integrations::Error) { @pack.set_review_check(@row, repository: "acme/web", sha: "a" * 40, check: check) }
          assert_match "Commit statuses write", error.message
        end
      end
    end
  end
end
