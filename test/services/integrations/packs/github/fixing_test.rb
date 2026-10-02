require "test_helper"

module Integrations
  module Packs
    class Github
      class FixingTest < ActiveSupport::TestCase
        setup do
          @workspace = workspaces(:slack_workspace_one)
          FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration, box_key: "investigation-1")
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:get).with("/repos/acme/api", token: "ghs_token").returns("default_branch" => "main")
          FirefightAi.stubs(:model_for).returns(FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"))
          FirefightAi.stubs(:priced?).returns(true)
          CodeReading.any_instance.stubs(:prepare).returns({})
          ENV.stubs(:[]).returns(nil)
          ENV.stubs(:[]).with("APP_HOST").returns("ff.example.com")
          ENV.stubs(:fetch).with("APP_PROTOCOL", "https").returns("https")
        end

        test "the agent runs in the writable copy with a config that reaches only Firefight, and its change opens as a pull request" do
          sent = nil
          CodeReading.any_instance.expects(:exec).with do |repo, ref:, where:, argv:, timeout:|
            sent = argv
            repo == "acme/api" && ref == "main" && where == Sandboxes::Client::IN_COPY && timeout == Fixing::FIX_TIMEOUT
          end.returns("stdout" => agent_output, "exit_code" => 0, "timed_out" => false, "commit" => "abc")
          GithubApp.expects(:open_pull_request).with do |repo, base:, base_sha:, branch:, title:, files:, body:, **|
            repo == "acme/api" && base == "main" && base_sha == "start-sha" && branch.start_with?(Fixing::BRANCH_PREFIX) && title == "Restore the pool size" &&
              files == { "config/database.yml" => { mode: "100644", content: Base64.strict_encode64("pool: 10\n") }, "old name.rb" => nil } &&
              body.start_with?("Put the pool back to 10") && !body.include?("evidence from the logs") && body.include?("[REDACTED:github_token]")
          end.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Restore the pool size",
                                                                     "brief" => "The pool went from 10 to 2, evidence from the logs",
                                                                     "summary" => "Put the pool back to 10. ghp_#{'a' * 36}" })

          assert_equal "Opened https://github.com/acme/api/pull/7 on acme/api against main.\nconfig/database.yml | 2 +-", text
          config = JSON.parse(sent[4])
          assert_equal "https://ff.example.com/code_agent/anthropic", config.dig("provider", "anthropic", "options", "baseURL")
          assert_equal({ "edit" => "allow", "bash" => "allow", "webfetch" => "deny", "websearch" => "deny" }, config["permission"])
          assert_equal "anthropic/claude-sonnet-4-5", sent[6]
          session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
          assert_equal session, CodeAgentSession.where(id: session.id).where.not(closed_at: nil).sole, "the session ends with the change"
          assert_nil CodeAgentSession.authenticate(config.dig("provider", "anthropic", "options", "apiKey"))
        end

        test "an agent that changed nothing opens nothing and says what it said" do
          CodeReading.any_instance.stubs(:exec).returns("stdout" => "AGENT_EXIT 0\nBASE start-sha\nSTAT\n\nLOG\nI could not find the pool setting.", "timed_out" => false)
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_match "The coding agent changed nothing in acme/api.\nI could not find the pool setting.", error.message
        end

        test "a model Firefight cannot reach from the sandbox is said before anything runs" do
          FirefightAi.stubs(:model_for).returns(FirefightAi::ModelChoice.new(model: "gemini-2.5-pro", provider: "gemini"))
          CodeReading.any_instance.expects(:exec).never

          assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
        end

        test "a change to CI, from an agent that failed, or cut short, is never opened" do
          GithubApp.expects(:open_pull_request).never
          arguments = { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }

          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output(path: ".github/workflows/ci.yml"), "timed_out" => false)
          assert_match "runs in CI with the repository's secrets", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output(exit: 1), "timed_out" => false)
          assert_match "stopped with an error", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false, "truncated" => true)
          assert_match "too large for the sandbox", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          nested = "AGENT_EXIT 0\nBASE s\nNESTED\t#{Base64.strict_encode64('vendor/lib')}\nSTAT\n\nLOG\n"
          CodeReading.any_instance.stubs(:exec).returns("stdout" => nested, "timed_out" => false)
          assert_match "a repository inside this one", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message
        end

        private

        def agent_output(path: "config/database.yml", exit: 0)
          "AGENT_EXIT #{exit}\nBASE start-sha\nFILE\t100644\t#{Base64.strict_encode64(path)}\t#{Base64.strict_encode64("pool: 10\n")}\n" \
            "GONE\t#{Base64.strict_encode64('old name.rb')}\nSTAT\n config/database.yml | 2 +-\nLOG\ndone"
        end
      end
    end
  end
end
