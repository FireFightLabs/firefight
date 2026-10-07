require "test_helper"

module Integrations
  module Packs
    class Github
      class FixingTest < ActiveSupport::TestCase
        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration, box_key: "investigation-1")
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:get).with("/repos/acme/api", token: "ghs_token").returns("default_branch" => "main")
          FirefightAi.stubs(:choices_for).returns([ FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic") ])
          FirefightAi.stubs(:priced?).returns(true)
          CodeReading.any_instance.stubs(:prepare).returns({})
          ENV.stubs(:[]).returns(nil)
          ENV.stubs(:[]).with("APP_HOST").returns("ff.example.com")
          ENV.stubs(:fetch).with("APP_PROTOCOL", "https").returns("https")
        end

        test "the agent runs in the writable copy with a config that reaches only Firefight, and its change opens as a pull request" do
          sent = nil
          CodeReading.any_instance.expects(:exec).with do |repo, ref:, where:, argv:, timeout:, **|
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
          assert_equal "https://ff.example.com/code_agent/tools", config.dig("mcp", "firefight", "url")
          assert_equal "Bearer #{config.dig('provider', 'anthropic', 'options', 'apiKey')}", config.dig("mcp", "firefight", "headers", "Authorization")
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
          FirefightAi.stubs(:choices_for).returns([ FirefightAi::ModelChoice.new(model: "gemini-2.5-pro", provider: "gemini") ])
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

        test "what the agent does is reported as it happens, and the change ends with its files, tests and pull request" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          lines = file_fixture("opencode/fix_run.jsonl").read.lines
          CodeReading.any_instance.expects(:exec).with do |*, on_output:, **|
            on_output.call(lines.first(8).join)
            on_output.call("")
            on_output.call(lines.drop(8).join)
            true
          end.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          assert_equal [ 0, 1 ], heard.first(2).map { |update| update["lines"].size }, "nothing, then the copy is ready"
          assert_equal "Got acme/api ready at main", heard[1]["lines"].first["text"]
          during = heard[2]
          assert during["live"]
          assert_includes during["lines"].map { |line| line["text"] }, "Read config/database.yml"
          assert_nil during["finishedAt"]
          last = Chat::CodeFixProgress.from_h(heard.last)
          assert_equal Chat::CodeFixProgress::OUTCOME_OPENED, last.outcome
          assert_equal "https://github.com/acme/api/pull/7", last.pull_request
          assert_equal [ [ "config/database.yml", 1, 1 ] ], last.files.map { |file| [ file.path, file.added, file.removed ] }
          assert_equal [ [ "ruby test/pool_test.rb", true ] ], last.tests.map { |test| [ test.command, test.passed ] }
          assert_equal 15, last.total
        end

        test "a change that fails once the agent started ends its steps with why" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output(exit: 1), "timed_out" => false)

          assert_raises(Integrations::Error) { pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }

          last = Chat::CodeFixProgress.from_h(heard.last)
          assert_equal Chat::CodeFixProgress::OUTCOME_FAILED, last.outcome
          assert_equal "The coding agent stopped with an error, so its change is not opened.", last.reason
          refute last.live?, "an older sandbox never says what the agent does"
        end

        test "a change asked for an open pull request is written on its head and pushed to its branch, and the pull request is told" do
          stub_pull(7)
          stub_branch("fix-pool")
          CodeReading.any_instance.expects(:exec).with { |repo, ref:, **| repo == "acme/api" && ref == "h" * 40 }
                     .returns("stdout" => agent_output.sub("BASE start-sha", "BASE #{'h' * 40}"), "timed_out" => false)
          GithubApp.expects(:open_pull_request).never
          GithubApp.expects(:push_commit).with do |repo, branch:, base_sha:, message:, files:, token:|
            repo == "acme/api" && branch == "fix-pool" && base_sha == "h" * 40 && message == "Raise the pool" && files.key?("config/database.yml") && token == "ghs_token"
          end.returns("n" * 40)
          GithubApp.expects(:write).with do |verb, path, body, token:|
            verb == :post && path == "/repos/acme/api/issues/7/comments" && body[:body].start_with?("Firefight's coding agent added #{'n' * 12} to this pull request.") &&
              body[:body].include?("config/database.yml | 2 +-") && token == "ghs_token"
          end.returns({})

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it", "pull_request" => 7 })

          assert_equal "Pushed #{'n' * 12} to fix-pool in acme/api, updating https://github.com/acme/api/pull/7. Said so on the pull request.\nconfig/database.yml | 2 +-", text
        end

        test "a change added to an open pull request ends its steps with the pull request it went to" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          stub_pull(7)
          stub_branch("fix-pool")
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output.sub("BASE start-sha", "BASE #{'h' * 40}"), "timed_out" => false)
          GithubApp.stubs(:push_commit).returns("n" * 40)
          GithubApp.stubs(:write).returns({})

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise", "brief" => "Raise it", "pull_request" => 7 })

          last = Chat::CodeFixProgress.from_h(heard.last)
          assert_equal Chat::CodeFixProgress::OUTCOME_PUSHED, last.outcome
          assert_equal "https://github.com/acme/api/pull/7", last.pull_request
          assert_equal [ "config/database.yml" ], last.files.map(&:path)
          assert_match "Added to the pull request", last.headline
        end

        test "a branch name finds its open pull request to tell" do
          stub_branch("fix-pool")
          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:fix-pool', 'per_page' => 1 }.to_query}", token: "ghs_token")
                   .returns([ pull(7) ])
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:push_commit).returns("n" * 40)
          GithubApp.expects(:write).returns({})

          assert_match "Pushed #{'n' * 12} to fix-pool in acme/api, updating https://github.com/acme/api/pull/7.",
                       @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise", "brief" => "Raise it", "branch" => "fix-pool" })
        end

        test "nothing is pushed to a fork, the default branch, a protected branch, a branch a ruleset guards, or a closed pull request" do
          CodeReading.any_instance.expects(:exec).never
          GithubApp.expects(:push_commit).never
          arguments = { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }

          stub_pull(7, "head" => { "ref" => "patch-1", "sha" => "h" * 40, "repo" => { "full_name" => "someone/api" } })
          assert_equal "PR #7 in acme/api comes from someone/api, and Firefight adds only to a branch in acme/api itself.",
                       assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("pull_request" => 7)) }.message

          stub_pull(8, "state" => "closed")
          assert_equal "PR #8 in acme/api is closed, so nothing is added to it.",
                       assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("pull_request" => 8)) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:main', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          assert_equal "main is the default branch of acme/api, and a code change reaches it only through a pull request.",
                       assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "main")) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:release', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          stub_branch("release", protected: true)
          assert_equal "release in acme/api is protected, so Firefight does not push to it.",
                       assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "release")) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:ruled', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          stub_branch("ruled", rules: [ { "type" => "pull_request" } ])
          assert_equal "A ruleset in acme/api keeps pushes off ruled, so Firefight does not push to it.",
                       assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "ruled")) }.message
        end

        test "a branch that moved while the agent worked is never overwritten" do
          stub_pull(7)
          stub_branch("fix-pool")
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:push_commit).raises(GithubApp::Error, "GitHub answered 422: Update is not a fast forward")
          GithubApp.expects(:write).never

          error = assert_raises(Integrations::Error) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it", "pull_request" => 7 })
          end

          assert_equal "GitHub did not move fix-pool to the new commit: GitHub answered 422: Update is not a fast forward. Someone may have pushed to it while " \
                       "the agent worked, so nothing was overwritten. Ask again to write it on the new head.", error.message
        end

        private

        def pull(number, overrides = {})
          { "number" => number, "state" => "open", "merged_at" => nil, "html_url" => "https://github.com/acme/api/pull/#{number}",
            "head" => { "ref" => "fix-pool", "sha" => "h" * 40, "repo" => { "full_name" => "acme/api" } } }.merge(overrides)
        end

        def stub_pull(number, overrides = {})
          GithubApp.stubs(:get).with("/repos/acme/api/pulls/#{number}", token: "ghs_token").returns(pull(number, overrides))
        end

        def stub_branch(name, protected: false, rules: [])
          GithubApp.stubs(:get).with("/repos/acme/api/branches/#{name}", token: "ghs_token").returns("protected" => protected, "commit" => { "sha" => "h" * 40 })
          GithubApp.stubs(:get).with("/repos/acme/api/rules/branches/#{name}?per_page=100", token: "ghs_token").returns(rules)
        end

        def agent_output(path: "config/database.yml", exit: 0)
          "AGENT_EXIT #{exit}\nBASE start-sha\nCOUNT\t1\t1\t#{Base64.strict_encode64(path)}\nFILE\t100644\t#{Base64.strict_encode64(path)}\t#{Base64.strict_encode64("pool: 10\n")}\n" \
            "GONE\t#{Base64.strict_encode64('old name.rb')}\nSTAT\n config/database.yml | 2 +-\nLOG\ndone"
        end
      end
    end
  end
end
