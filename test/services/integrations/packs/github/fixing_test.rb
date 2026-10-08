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
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).returns(review)
        end

        test "the agent runs in the writable copy with a config that reaches only Firefight, and its change opens as a pull request" do
          sent = nil
          CodeReading.any_instance.expects(:exec).with do |repo, ref:, where:, argv:, timeout:, **|
            sent = argv
            repo == "acme/api" && ref == "main" && where == Sandboxes::Client::IN_COPY &&
              timeout == Fixing::FIX_TIMEOUT + (CodeAgentQuestion::MAX_PER_CHANGE * CodeAgentQuestion::ANSWER_WITHIN).to_i
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

        test "a pull request of 0 and an empty branch, as a model fills fields it means to leave out, open a new pull request" do
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:push_commit).never
          GithubApp.expects(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/8")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it",
                                                                     "base" => "main", "pull_request" => 0, "branch" => "" })

          assert_match "Opened https://github.com/acme/api/pull/8", text
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

        test "a change from an agent that failed, or cut short, is never opened" do
          GithubApp.expects(:open_pull_request).never
          arguments = { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }

          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output(exit: 1), "timed_out" => false)
          assert_match "stopped with an error", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false, "truncated" => true)
          assert_match "too large for the sandbox", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          nested = "AGENT_EXIT 0\nBASE s\nNESTED\t#{Base64.strict_encode64('vendor/lib')}\nSTAT\n\nLOG\n"
          CodeReading.any_instance.stubs(:exec).returns("stdout" => nested, "timed_out" => false)
          assert_match "a repository inside this one", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message
        end

        test "a change to CI opens by default, and its pull request and answer lead with a warning" do
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output(path: ".github/workflows/release.yml"), "timed_out" => false)
          GithubApp.expects(:open_pull_request).with do |_repo, body:, **|
            body.start_with?("#{CodeChange::CI_WARNING}\n\nPin the release action")
          end.returns("html_url" => "https://github.com/acme/api/pull/9")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Pin the release action", "brief" => "Pin it",
                                                                     "summary" => "Pin the release action" })

          assert text.start_with?("#{CodeChange::CI_WARNING}\nOpened https://github.com/acme/api/pull/9 on acme/api against main.")
        end

        test "a change to a path the connection keeps out is refused with where the list is, and the agent is told the list" do
          @integration.protect_paths!([ ".github/workflows/", "*.lock" ])
          brief = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| brief = argv[5] }
                     .returns("stdout" => agent_output(path: ".github/workflows/release.yml"), "timed_out" => false)
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(PolicyRefusal) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_equal "Halon may not change .github/workflows/release.yml in acme/api. An admin can change this under Integrations, GitHub, Code changes.", error.message
          assert_includes brief, "Leave .github/workflows/ and *.lock unchanged, since this workspace keeps those paths out of code changes."
        end

        test "a change outside the paths the connection keeps out opens as before, and the brief names nothing when it keeps none" do
          brief = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| brief = argv[5] }.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          refute_includes brief, "unchanged, since this workspace keeps"
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
          assert_equal 17, last.total, "the agent's steps, then the review"
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

        test "a CI change pushed to an open pull request leads its comment and the answer with the warning, and a kept path is never pushed" do
          stub_pull(7)
          stub_branch("fix-pool")
          output = agent_output(path: ".gitlab-ci.yml").sub("BASE start-sha", "BASE #{'h' * 40}")
          CodeReading.any_instance.stubs(:exec).returns("stdout" => output, "timed_out" => false)
          GithubApp.expects(:push_commit).returns("n" * 40)
          GithubApp.expects(:write).with { |_verb, _path, body, **| body[:body].start_with?("#{CodeChange::CI_WARNING}\n\nFirefight's coding agent added") }.returns({})
          arguments = { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it", "pull_request" => 7 }

          assert @pack.fix_code(environment_row: @row, arguments: arguments).start_with?("#{CodeChange::CI_WARNING}\nPushed #{'n' * 12} to fix-pool")

          @integration.protect_paths!([ ".gitlab-ci.yml" ])
          GithubApp.expects(:push_commit).never
          assert_match "Halon may not change .gitlab-ci.yml in acme/api.", assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message
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
                       assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("pull_request" => 7)) }.message

          stub_pull(8, "state" => "closed")
          assert_equal "PR #8 in acme/api is closed, so nothing is added to it.",
                       assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("pull_request" => 8)) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:main', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          assert_equal "main is the default branch of acme/api, and a code change reaches it only through a pull request.",
                       assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "main")) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:release', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          stub_branch("release", protected: true)
          assert_equal "release in acme/api is protected, so Firefight does not push to it.",
                       assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "release")) }.message

          GithubApp.stubs(:get).with("/repos/acme/api/pulls?#{{ 'state' => 'open', 'head' => 'acme:ruled', 'per_page' => 1 }.to_query}", token: "ghs_token").returns([])
          stub_branch("ruled", rules: [ { "type" => "pull_request" } ])
          assert_equal "A ruleset in acme/api keeps pushes off ruled, so Firefight does not push to it.",
                       assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments.merge("branch" => "ruled")) }.message
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

        test "the agent's brief carries the person's own words and what Halon read, scrubbed, and its Firefight tools are on with web search off" do
          @workspace.update!(web_search_enabled: false)
          request = CodeAgent::Request.new(
            principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
            words: [ "Make the release job send the commit", "No, send the tag, not the commit" ],
            evidence: [ CodeAgent::Request::Evidence.new(label: "Fetch file release.yml", text: "on: release\ntoken ghp_#{'a' * 36}") ]
          )
          pack = Github.new(@integration, box_key: "investigation-1", request: request)
          sent = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| sent = argv }.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send the release tag" })

          brief = sent[5]
          assert_includes brief, "What the person asked, in their own words, oldest first. A later message corrects an earlier one:\n> Make the release job send the commit\n\n> No, send the tag, not the commit"
          assert_includes brief, "<tool_result tool=\"Fetch file release.yml\" trust=\"untrusted\">\non: release\ntoken [REDACTED:github_token]"
          assert_includes brief, "read that system's documented contract and how it is set up now"
          refute_includes brief, "ghp_"
          config = JSON.parse(sent[4])
          assert config.dig("mcp", "firefight", "enabled"), "the read tools and questions need the server even without web search"
          session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
          assert_equal [ workspace_memberships(:alice_workspace_one), "investigation-1" ], [ session.principal, session.box_key ]
        end

        test "a change the review finds wrong goes back to the agent once with the findings and the earlier change, and opens once it is right" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review)
                                     .returns(review(right: false, findings: [ "The workflow sends the commit in a body the provider ignores." ]))
                                     .then.returns(review(unverified: [ "That the provider reads the tag from the ref." ]))
          runs = []
          CodeReading.any_instance.expects(:exec).twice.with { |*, argv:, timeout:, **| runs << [ argv[5], argv[7], timeout ] }
                     .returns("stdout" => agent_output(patch: "first change\n"), "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send the tag", "summary" => "Sends the tag" })

          assert_equal "", runs.first[1], "the first pass starts clean"
          assert_includes runs.last[0], "A review of your change found it does not yet do what was asked. Your change is already in the copy. Correct it:\n" \
                                         "- The workflow sends the commit in a body the provider ignores."
          assert_equal Base64.strict_encode64("first change\n"), runs.last[1], "the second pass starts from the first change"
          assert_operator runs.last[2], :<=, Fixing::SEND_BACK_TIMEOUT
          assert body.start_with?("### Check before merging\n\n**Not verified**\n- That the provider reads the tag from the ref.\n\nSends the tag"), body
          assert_includes text, "Halon's review sent the change back once, and the corrected change does what was asked."
          assert_includes text, "Not verified, so check before merging:\n- That the provider reads the tag from the ref."
        end

        test "a change still wrong after it was sent back is not opened, and says what the review found" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).returns(review(right: false, findings: [ "It still sends the commit." ]))
          CodeReading.any_instance.expects(:exec).twice.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send the tag" })
          end

          assert_equal "Halon's review still found the change wrong after sending it back once, so nothing is opened.\n- It still sends the commit.", error.message
        end

        test "what the review found and could not verify leads the pull request body, the checks follow it, and the review reads the person's words" do
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
                                           words: [ "Send the tag" ])
          pack = Github.new(@integration, box_key: "investigation-1", request: request)
          FirefightAi::ChangeReviewer.any_instance.expects(:review).with do |asked:, checks:, diff:, **|
            asked == "1. Send the tag" && checks.include?("- actionlint .github/workflows/release.yml: failed\nline 3: unknown key") && diff.include?("+pool: 10")
          end.returns(review(findings: [ "No test covers the new input." ], unverified: [ "That the provider reads the tag." ]))
          output = agent_output(path: ".github/workflows/release.yml", checks: check_line("actionlint .github/workflows/release.yml", 1, "line 3: unknown key") +
                                                                            check_line("yaml .github/workflows/release.yml", 0))
          CodeReading.any_instance.stubs(:exec).returns("stdout" => output, "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/9")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send it", "summary" => "Sends the tag" })

          assert body.start_with?("#{CodeChange::CI_WARNING}\n\n### Check before merging\n\n**What Halon's review found**\n- No test covers the new input.\n\n" \
                                  "**Not verified**\n- That the provider reads the tag.\n\nSends the tag"), body
          assert_includes body, "Checks run in Firefight's sandbox on the changed files:\n- `actionlint .github/workflows/release.yml`: failed\n- `yaml .github/workflows/release.yml`: passed"
        end

        test "a review that cannot run opens the change saying nothing was checked" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).raises(FirefightAi::TransientError.new(reason: "Timeout"))
          CodeReading.any_instance.stubs(:exec).returns("stdout" => agent_output, "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          assert body.start_with?("### Check before merging\n\n**Not verified**\n- Halon's review could not run"), body
          assert_includes text, "Not verified, so check before merging:\n- Halon's review could not run"
        end

        test "a question nobody answered in time ends the change with the question, and the step shows it" do
          heard = []
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
                                           place: @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: workspace_memberships(:alice_workspace_one),
                                                                                    max_turns: 10, max_spend_cents: 50))
          pack = Github.new(@integration, box_key: "investigation-1", request: request, progress: ->(update) { heard << update.to_h.deep_dup })
          CodeReading.any_instance.expects(:exec).with do |*, on_output:, **|
            session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
            CodeAgentQuestion.ask!(session, "Should the job send the tag or the commit?")
            on_output.call("")
            travel CodeAgentQuestion::ANSWER_WITHIN + 1.second
            on_output.call("")
            true
          end.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) do
            pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_equal "The coding agent asked a question nobody answered within 5 minutes, so nothing is opened: Should the job send the tag or the commit?", error.message
          waiting = heard.map { |update| Chat::CodeFixProgress.from_h(update) }.find(&:waiting_for_answer?)
          assert_equal "Waiting for an answer: Should the job send the tag or the commit?", waiting.headline.split(" · ").first
          assert_equal CodeAgentQuestion::STATUS_EXPIRED, Chat::CodeFixProgress.from_h(heard.last).question["status"]
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

        def agent_output(path: "config/database.yml", exit: 0, checks: "", patch: "diff --git a/#{path} b/#{path}\n-pool: 2\n+pool: 10\n")
          "AGENT_EXIT #{exit}\nBASE start-sha\n#{checks}COUNT\t1\t1\t#{Base64.strict_encode64(path)}\nFILE\t100644\t#{Base64.strict_encode64(path)}\t#{Base64.strict_encode64("pool: 10\n")}\n" \
            "GONE\t#{Base64.strict_encode64('old name.rb')}\nPATCH\t#{Base64.strict_encode64(patch)}\nSTAT\n config/database.yml | 2 +-\nLOG\ndone"
        end

        def check_line(name, code, output = "")
          "CHECK\t#{Base64.strict_encode64(name)}\t#{code}\t#{Base64.strict_encode64(output)}\n"
        end

        def review(right: true, findings: [], unverified: [])
          FirefightAi::ChangeReviewer::Review.new(right: right, findings: findings, unverified: unverified, summary: "Sets the pool to 10.")
        end
      end
    end
  end
end
