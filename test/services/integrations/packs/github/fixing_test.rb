require "test_helper"

module Integrations
  module Packs
    class Github
      class FixingTest < ActiveSupport::TestCase
        include CodeQuestionTestHelper
        include ActiveJob::TestHelper
        NEWEST = "n" * 40
        CHANGED = "c" * 40
        PUSHED = "To https://ff.example.com/code_agent/git/change.git\n*\trefs/halon/x:refs/heads/x\t[new branch]\nDone\nPUSH_EXIT 0\n".freeze

        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration, box_key: "investigation-1")
          GithubApp.stubs(:installation_token).returns("ghs_token")
          GithubApp.stubs(:get).with("/repos/acme/api", token: "ghs_token").returns("default_branch" => "main")
          FirefightAi.stubs(:choices_for).returns([ FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic") ])
          FirefightAi.stubs(:priced_for?).returns(true)
          CodeReading.any_instance.stubs(:prepare).returns({})
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.returns("stdout" => PUSHED)
          stub_compare([ "config/database.yml" ])
          GithubApp.stubs(:get).with("/repos/acme/api/branches/main", token: "ghs_token").returns("commit" => { "sha" => NEWEST })
          Github.any_instance.stubs(:pull_request_status).returns(
            Integrations::PullRequests::Status.new(number: 7, state: Integrations::PullRequests::OPEN, mergeable: Integrations::PullRequests::MERGEABLE, head_sha: "h", base: "main")
          )
          AppUrl.stubs(:root).returns("https://ff.example.com")
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).returns(review)
        end

        test "the agent runs in the writable copy with a config that reaches only Firefight, and its change opens as a pull request" do
          sent = nil
          told = nil
          pushed = nil
          push_told = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, stdin:, **| argv[2] == Fixing::PUSH && (pushed = argv) && (push_told = stdin) }.returns("stdout" => PUSHED)
          CodeReading.any_instance.expects(:exec).with do |repo, ref:, where:, argv:, timeout:, stdin:, **|
            argv[2] == Fixing::RUN && (sent = argv) && (told = stdin) &&
            repo == "acme/api" && ref == NEWEST && where == Sandboxes::Client::IN_COPY &&
              timeout == Fixing::FIX_TIMEOUT + (CodeAgentQuestion::MAX_PER_CHANGE * CodeAgentQuestion::ANSWER_WITHIN).to_i
          end.returns("stdout" => agent_output, "exit_code" => 0, "timed_out" => false, "commit" => "abc")
          GithubApp.expects(:open_pull_request).with do |repo, base:, branch:, title:, body:, token:|
            repo == "acme/api" && base == "main" && branch.start_with?(Fixing::BRANCH_PREFIX) && title == "Restore the pool size" && token == "ghs_token" &&
              body.start_with?("Put the pool back to 10") && !body.include?("evidence from the logs") && body.include?("[REDACTED:github_token]")
          end.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Restore the pool size",
                                                                     "brief" => "The pool went from 10 to 2, evidence from the logs",
                                                                     "summary" => "Put the pool back to 10. ghp_#{'a' * 36}" })

          assert_equal "Opened https://github.com/acme/api/pull/7 on acme/api against main.\n\nChanges:\n- `config/database.yml` (+1 -1)\n\n" \
                       "The code host says PR #7 can merge into main. Say only this about whether it can merge, never more than the code host said.", text
          credential, config_line = told.lines.map(&:chomp)
          config = JSON.parse(config_line)
          assert_equal "https://ff.example.com/code_agent/anthropic", config.dig("provider", "anthropic", "options", "baseURL")
          assert_equal({ "edit" => "allow", "bash" => "allow", "webfetch" => "deny", "websearch" => "deny",
                         "external_directory" => { "{env:TMPDIR}/*" => "allow" } }, config["permission"], "its own temporary files are its to use, nothing else outside the copy")
          assert_equal "https://ff.example.com/code_agent/tools", config.dig("mcp", "firefight", "url")
          assert_equal "Bearer #{config.dig('provider', 'anthropic', 'options', 'apiKey')}", config.dig("mcp", "firefight", "headers", "Authorization")
          assert_equal "anthropic/claude-sonnet-4-5", sent[5]
          session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
          assert_equal session, CodeAgentSession.where(id: session.id).where.not(closed_at: nil).sole, "the session ends with the change"
          assert_nil CodeAgentSession.authenticate(config.dig("provider", "anthropic", "options", "apiKey"))
          token = config.dig("provider", "anthropic", "options", "apiKey")
          assert_equal [ "https://ff.example.com/code_agent/git/change.git", "main", "Restore the pool size" ], sent.values_at(7, 8, 10)
          assert_equal Base64.strict_encode64("halon:#{token}"), credential, "git fetches through the gate with the session's token, never GitHub's"
          assert(sent.none? { |word| word.include?(token) }, "no credential is an argument any process in the box can read")
          branch = sent[9]
          assert branch.start_with?(Fixing::BRANCH_PREFIX)
          assert_equal [ "https://ff.example.com/code_agent/git/change.git", branch, "" ], pushed.values_at(4, 5, 6), "a new branch is pushed only if nobody made it"
          push_credential = Base64.strict_decode64(push_told.chomp).delete_prefix("halon:")
          assert_not_equal token, push_credential, "the push signs in with a token of its own, which the agent never held"
          assert(pushed.none? { |word| word.include?(push_credential) })
          assert_nil CodeAgentSession.authenticate_push(push_credential), "the push token works only while the push runs"
          assert_equal [ @row.id, branch ], [ session.integration_environment_id, session.git_branch ]
          assert_includes sent[4], "a normal git repository on the branch #{branch}"
        end

        test "a pull request of 0 and an empty branch, as a model fills fields it means to leave out, open a new pull request" do
          stub_run("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/8")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it",
                                                                     "base" => "main", "pull_request" => 0, "branch" => "" })

          assert_match "Opened https://github.com/acme/api/pull/8", text
        end

        test "an agent that changed nothing opens nothing and says what it said" do
          said = { type: "text", part: { text: "I could not find the pool setting." } }.to_json
          stub_run("stdout" => "AGENT_EXIT 0\nBASE start-sha\nNOTHING\nLOG\n#{said}", "timed_out" => false)
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_match "The coding agent changed nothing in acme/api.\nI could not find the pool setting.", error.message
        end

        test "a provider's error stops the change with a plain sentence, and its headers and body go only to the log" do
          error_event = { type: "error", error: { name: "APIError", data: { message: "Overloaded", statusCode: 529,
                                                                            responseHeaders: { "cf-ray" => "8f1-AMS", "x-request-id" => "req_1" },
                                                                            responseBody: "{\"type\":\"error\"}" } } }.to_json
          stub_run("stdout" => agent_output(exit: 1).sub("LOG\ndone", "LOG\n#{error_event}"), "timed_out" => false)
          logged = []
          Rails.logger.stubs(:warn).with { |line| logged << line }

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }

          assert_equal "The coding agent stopped with an error (Overloaded), so its change is not opened.", error.message
          assert(logged.any? { |line| line.include?("code_fix.agent_failed") && line.include?("cf-ray") }, "the detail is kept for whoever reads the log")
        end

        test "a fetch or a push that fails says what failed in a sentence, with git's own words only in the log" do
          arguments = { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }
          logged = []
          Rails.logger.stubs(:warn).with { |line| logged << line }
          stub_run("stdout" => "FETCH_FAILED fatal: unable to access 'https://ff.example.com/code_agent/git/change.git/': The requested URL returned error: 502 ", "timed_out" => false)

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }
          assert_equal "The sandbox could not fetch the newest code from GitHub through Firefight, so nothing was written.", error.message
          assert(logged.any? { |line| line.include?("code_fix.fetch_failed") && line.include?("returned error: 502") })

          stub_run("stdout" => agent_output, "timed_out" => false)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }
                     .returns("stdout" => "error: RPC failed, HTTP 500 curl 22\nHTTP/1.1 500 Internal Server Error\nx-request-id: abc\nPUSH_EXIT 1\n")
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }
          assert_equal "The push through Firefight did not go through, so nothing was opened or changed.", error.message
          assert(logged.any? { |line| line.include?("code_fix.push_failed") && line.include?("x-request-id") })
        end

        test "a change whose tests could not run here still opens, with what could not run said in its pull request" do
          said = { type: "text", part: { text: "Raises the pool to 10.\n\nCould not run here:\n- `bin/rails test test/models/pool_test.rb`, since no database was there" } }.to_json
          checks = check_line("bin/rails test test/config/database_test.rb", 1, "PG::ConnectionBad: could not connect to server")
          stub_run("stdout" => agent_output(checks: checks).sub("LOG\ndone", "LOG\n#{said}"), "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it" })

          assert_includes body, "**Could not run here**\n- `bin/rails test test/config/database_test.rb`: no database was available.\n" \
                                "- `bin/rails test test/models/pool_test.rb`, since no database was there."
          assert_includes text, "Opened https://github.com/acme/api/pull/7"
          assert_includes text, "Could not run here:\n"
        end

        test "the agent writes the change first, never builds a database by hand, and lists what could not run" do
          brief = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && (brief = argv[4]) }.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          assert_includes brief, "Write the change first"
          assert_includes brief, "never a reason to stop or to leave the change unwritten"
          assert_includes brief, "Never build an environment, a database or a service by hand"
          assert_includes brief, "the sandbox's own way to start a service, when it offers one"
          assert_includes brief, "the repository's own CI runs on the pull request"
          assert_includes brief, "under a line that reads #{CodeWriteUp::NOT_RUN}:"
          assert_includes brief, "$TMPDIR"
        end

        test "a model Firefight cannot reach from the sandbox is said before anything runs" do
          FirefightAi.stubs(:choices_for).returns([ FirefightAi::ModelChoice.new(model: "gemini-2.5-pro", provider: "gemini") ])
          CodeReading.any_instance.expects(:exec).never

          assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
        end

        test "a change from an agent that failed, or cut short, is never opened" do
          GithubApp.expects(:open_pull_request).never
          arguments = { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }

          stub_run("stdout" => agent_output(exit: 1), "timed_out" => false)
          assert_match "stopped with an error", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          stub_run("stdout" => agent_output, "timed_out" => false, "truncated" => true)
          assert_match "too large for the sandbox", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message

          stub_run("stdout" => agent_output.sub("BYTES\t40", "BYTES\t#{Fixing::MAX_BYTES + 1}"), "timed_out" => false)
          assert_match "larger than 4 MB", assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message
        end

        test "a change to CI opens by default, and its pull request and answer lead with a warning" do
          stub_run("stdout" => agent_output(path: ".github/workflows/release.yml"), "timed_out" => false)
          stub_compare([ ".github/workflows/release.yml" ])
          GithubApp.expects(:open_pull_request).with do |_repo, body:, **|
            body.start_with?("Pin the release action\n\n#{CodeChange::CI_WARNING}")
          end.returns("html_url" => "https://github.com/acme/api/pull/9")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Pin the release action", "brief" => "Pin it",
                                                                     "summary" => "Pin the release action" })

          assert text.start_with?("Opened https://github.com/acme/api/pull/9 on acme/api against main.\n\n#{CodeChange::CI_WARNING}")
        end

        test "a change to a path the connection keeps out is refused before anything is pushed, with where the list is, and the agent is told the list" do
          @integration.protect_paths!([ ".github/workflows/", "*.lock" ])
          brief = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && (brief = argv[4]) }
                     .returns("stdout" => agent_output(path: ".github/workflows/release.yml"), "timed_out" => false)
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never
          GithubApp.expects(:write).never
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(PolicyRefusal) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_equal "Halon may not change .github/workflows/release.yml in acme/api. An admin can change this under Integrations, GitHub, Code changes.", error.message
          assert_includes brief, "Leave .github/workflows/ and *.lock unchanged, since this workspace keeps those paths out of code changes."
        end

        test "a change the box did not report under a kept path is still taken back once GitHub shows it landed there" do
          @integration.protect_paths!([ ".github/workflows/" ])
          stub_run("stdout" => agent_output, "timed_out" => false)
          stub_compare([ ".github/workflows/release.yml" ])
          GithubApp.expects(:write).with { |verb, path, **| verb == :delete && path.start_with?("/repos/acme/api/git/refs/heads/halon/fix-") }.returns({})
          GithubApp.expects(:open_pull_request).never

          assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
        end

        test "an agent stopped by a credit refusal on the deployment's keys never passes on what it said about the balance" do
          Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
          said = "AGENT_EXIT 1\nBASE start-sha\nSESSION \nFROM start-sha\nNOTHING\nLOG\n402 You requested up to 8000 tokens, but can only afford 120"
          stub_run("stdout" => said, "timed_out" => false)
          CodeAgentSession.any_instance.stubs(:house_refused_for_credit?).returns(true)

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
          assert_equal "Halon couldn't reach its AI just now. The team has been told.", error.message
        ensure
          Rails.configuration.x.install_notification_webhook_url = nil
        end

        test "an agent that failed or changed nothing never shows a credential from its log" do
          said = { type: "text", part: { text: "It needs DATABASE_URL=postgres://app:s3cret@db.internal/app" } }.to_json
          leaked = "AGENT_EXIT 0\nBASE start-sha\nSESSION \nFROM start-sha\nNOTHING\nLOG\n#{said}"
          stub_run("stdout" => leaked, "timed_out" => false)

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
          assert_match "[REDACTED:credential_url]db.internal/app", error.message
          assert_no_match "s3cret", error.message

          stub_run("stdout" => agent_output(exit: 1).sub("LOG\ndone", "LOG\nghp_#{'a' * 36}"), "timed_out" => false)
          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }
          assert_match "stopped with an error", error.message
          assert_no_match "ghp_", error.message
        end

        test "a change that breaks a rule once GitHub shows what it pushed is taken back: a new branch is deleted and nothing opens" do
          stub_run("stdout" => agent_output, "timed_out" => false)
          stub_compare([ "config/database.yml" ] + (1..Fixing::MAX_FILES).map { |index| "file_#{index}.rb" })
          GithubApp.expects(:write).with { |verb, path, **| verb == :delete && path.start_with?("/repos/acme/api/git/refs/heads/halon/fix-") }.returns({})
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }

          assert_equal "The change touches more than #{Fixing::MAX_FILES} files, which is not a fix, so it was taken back and nothing opened.", error.message
        end

        test "a change outside the paths the connection keeps out opens as before, and the brief names nothing when it keeps none" do
          brief = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && (brief = argv[4]) }.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          refute_includes brief, "unchanged, since this workspace keeps"
        end

        test "what the agent does is reported as it happens, and the change ends with its files, tests and pull request" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          lines = file_fixture("opencode/fix_run.jsonl").read.lines
          CodeReading.any_instance.expects(:exec).with do |*, argv:, on_output: nil, **|
            next false unless argv[2] == Fixing::RUN

            on_output.call(lines.first(8).join)
            on_output.call("")
            on_output.call(lines.drop(8).join)
            true
          end.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          assert_equal [ 0, 1 ], heard.first(2).map { |update| update["lines"].size }, "nothing, then the copy is ready"
          assert_equal "Got acme/api ready at main (#{NEWEST[0, 12]})", heard[1]["lines"].first["text"]
          during = heard[2]
          assert during["live"]
          assert_includes during["lines"].map { |line| line["text"] }, "Read config/database.yml"
          assert_nil during["finishedAt"]
          last = Chat::CodeFixProgress.from_h(heard.last)
          assert_equal Chat::CodeFixProgress::OUTCOME_OPENED, last.outcome
          assert_equal "https://github.com/acme/api/pull/7", last.pull_request
          assert_equal [ [ "config/database.yml", 1, 1 ] ], last.files.map { |file| [ file.path, file.added, file.removed ] }
          assert_equal [ [ "ruby test/pool_test.rb", true ] ], last.tests.map { |test| [ test.command, test.passed ] }
          assert_equal 18, last.total, "the agent's steps, the review, then the push"
        end

        test "a change that fails once the agent started ends its steps with why" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          stub_run("stdout" => agent_output(exit: 1), "timed_out" => false)

          assert_raises(Integrations::Error) { pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }) }

          last = Chat::CodeFixProgress.from_h(heard.last)
          assert_equal Chat::CodeFixProgress::OUTCOME_FAILED, last.outcome
          assert_equal "The coding agent stopped with an error, so its change is not opened.", last.reason
          refute last.live?, "an older sandbox never says what the agent does"
        end

        test "a change asked for an open pull request is written on its head and pushed to its branch, and the pull request is told" do
          stub_pull(7)
          stub_branch("fix-pool")
          CodeReading.any_instance.expects(:exec).with { |repo, ref:, argv:, **| argv[2] == Fixing::RUN && repo == "acme/api" && ref == "h" * 40 && argv.values_at(8, 9) == %w[main fix-pool] }
                     .returns("stdout" => agent_output.sub("BASE start-sha", "BASE #{'h' * 40}"), "timed_out" => false)
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH && argv.values_at(5, 6) == [ "fix-pool", "h" * 40 ] }.returns("stdout" => PUSHED)
          GithubApp.expects(:open_pull_request).never
          GithubApp.expects(:write).with do |verb, path, body, token:|
            verb == :post && path == "/repos/acme/api/issues/7/comments" && body[:body].start_with?("Raise the pool\n\nChanged in this update: `config/database.yml`.") &&
              body[:body].end_with?("Added by Halon in #{'c' * 12}. Review it like any other change before merging.") && token == "ghs_token"
          end.returns({})

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it", "pull_request" => 7 })

          assert_equal "Pushed #{'c' * 12} to fix-pool in acme/api, updating https://github.com/acme/api/pull/7. Said so on the pull request.\n\n" \
                       "Changed in this update: `config/database.yml`.\n\nThe code host says PR #7 can merge into main. Say only this about whether it can merge, never more than the code host said.", text
        end

        test "a merge with the base the agent made on the branch is pushed as it is, and the answer says only what the host says" do
          stub_pull(7)
          stub_branch("fix-pool")
          GithubApp.stubs(:write).returns({})
          @integration.protect_paths!([ "notes.txt" ])
          merged = agent_output.sub("BASE start-sha", "BASE #{'h' * 40}")
          stub_run("stdout" => merged, "timed_out" => false)
          stub_compare([ "config/database.yml" ], from: "main")
          stub_compare([ "config/database.yml", "notes.txt" ], from: "h" * 40)
          Github.any_instance.stubs(:pull_request_status).returns(
            Integrations::PullRequests::Status.new(number: 7, state: Integrations::PullRequests::OPEN, mergeable: Integrations::PullRequests::MERGEABLE, head_sha: CHANGED, base: "main")
          )

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Merge main", "brief" => "Merge main and resolve it", "pull_request" => 7 })

          assert_includes text, "Pushed #{'c' * 12} to fix-pool", "what the base brought, notes.txt here, is not the change's, so its kept path does not refuse it"
          assert_includes text, "The code host says PR #7 can merge into main."
        end

        test "conflict markers left in a file are never pushed" do
          stub_pull(7)
          stub_branch("fix-pool")
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never
          marked = agent_output.sub("BASE start-sha", "BASE #{'h' * 40}\nUNRESOLVED\t#{Base64.strict_encode64('config/database.yml')}")
          stub_run("stdout" => marked, "timed_out" => false)

          error = assert_raises(Integrations::Error) { @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Merge", "brief" => "Resolve", "pull_request" => 7 }) }
          assert_equal "The coding agent left conflict markers in config/database.yml, so nothing is pushed.", error.message
        end

        test "a CI change pushed to an open pull request leads its comment and the answer with the warning, and a kept path is never pushed" do
          stub_pull(7)
          stub_branch("fix-pool")
          output = agent_output(path: ".gitlab-ci.yml").sub("BASE start-sha", "BASE #{'h' * 40}")
          stub_run("stdout" => output, "timed_out" => false)
          stub_compare([ ".gitlab-ci.yml" ])
          GithubApp.expects(:write).with { |_verb, _path, body, **| body[:body].to_s.start_with?("Raise the pool\n\n#{CodeChange::CI_WARNING}\n\nChanged in this update") }.returns({})
          arguments = { "repo" => "acme/api", "title" => "Raise the pool", "brief" => "Raise it", "pull_request" => 7 }

          assert_match(/\APushed #{'c' * 12} to fix-pool.*\n\n#{Regexp.escape(CodeChange::CI_WARNING)}/, @pack.fix_code(environment_row: @row, arguments: arguments))

          @integration.protect_paths!([ ".gitlab-ci.yml" ])
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never
          assert_match "Halon may not change .gitlab-ci.yml in acme/api.", assert_raises(PolicyRefusal) { @pack.fix_code(environment_row: @row, arguments: arguments) }.message
        end

        test "a change added to an open pull request ends its steps with the pull request it went to" do
          heard = []
          pack = Github.new(@integration, box_key: "investigation-1", progress: ->(update) { heard << update.to_h.deep_dup })
          stub_pull(7)
          stub_branch("fix-pool")
          stub_run("stdout" => agent_output.sub("BASE start-sha", "BASE #{'h' * 40}"), "timed_out" => false)
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
          stub_run("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:write).returns({})

          assert_match "Pushed #{'c' * 12} to fix-pool in acme/api, updating https://github.com/acme/api/pull/7.",
                       @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise", "brief" => "Raise it", "branch" => "fix-pool" })
        end

        test "nothing is pushed to a fork, the default branch, a protected branch, a branch a ruleset guards, or a closed pull request" do
          CodeReading.any_instance.expects(:exec).never
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
          stub_run("stdout" => agent_output, "timed_out" => false)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }
                     .returns("stdout" => "To gate\n!\trefs/halon/fix-pool:refs/heads/fix-pool\t[rejected] (stale info)\nDone\nPUSH_EXIT 1\n")
          GithubApp.expects(:write).never

          error = assert_raises(Integrations::Error) do
            @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it", "pull_request" => 7 })
          end

          assert_equal "GitHub did not move fix-pool to the new commit. Someone may have pushed to it while the agent worked, so nothing was overwritten. " \
                       "Ask again to write it on the new head.", error.message
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
          told = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, stdin:, **| argv[2] == Fixing::RUN && (sent = argv) && (told = stdin) }
                     .returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send the release tag" })

          brief = sent[4]
          assert_includes brief, "What the person asked, in their own words, oldest first. A later message corrects an earlier one. #{FirefightAi::Copy::QUOTING}\n> Make the release job send the commit\n\n> No, send the tag, not the commit"
          assert_includes brief, "<tool_result tool=\"Fetch file release.yml\" trust=\"untrusted\">\non: release\ntoken [REDACTED:github_token]"
          assert_includes brief, "read that system's documented contract and how it is set up now"
          refute_includes brief, "ghp_"
          config = JSON.parse(told.lines.second)
          assert config.dig("mcp", "firefight", "enabled"), "the read tools and questions need the server even without web search"
          session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
          assert_equal [ workspace_memberships(:alice_workspace_one), "investigation-1" ], [ session.principal, session.box_key ]
        end

        test "a change the review finds wrong goes back to the agent once with the findings and the earlier change, and opens once it is right" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review)
                                     .returns(review(right: false, findings: [ "The workflow sends the commit in a body the provider ignores." ]))
                                     .then.returns(review(unverified: [ "That the provider reads the tag from the ref." ]))
          runs = []
          CodeReading.any_instance.expects(:exec).twice.with { |*, argv:, timeout:, **| argv[2] == Fixing::RUN && (runs << [ argv[4], argv[6], timeout ]) }
                     .returns("stdout" => agent_output, "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send the tag", "summary" => "Sends the tag" })

          assert_equal "", runs.first[1], "the first pass starts clean"
          assert_includes runs.last[0], "A review of your change found it does not yet do what was asked. Your change is already on the branch. Correct it:\n" \
                                         "- The workflow sends the commit in a body the provider ignores."
          assert_equal CHANGED, runs.last[1], "the second pass starts from the first change"
          assert_operator runs.last[2], :<=, Fixing::SEND_BACK_TIMEOUT
          assert body.start_with?("Sends the tag\n\n**Open questions**\n- That the provider reads the tag from the ref."), body
          assert_includes text, "Open questions:\n- That the provider reads the tag from the ref."
        end

        test "a change still wrong after it was sent back is not opened, and says what the review found" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).returns(review(right: false, findings: [ "It still sends the commit." ]))
          CodeReading.any_instance.expects(:exec).twice.with { |*, argv:, **| argv[2] == Fixing::RUN }.returns("stdout" => agent_output, "timed_out" => false)
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
          stub_run("stdout" => output, "timed_out" => false)
          stub_compare([ ".github/workflows/release.yml" ])
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/9")

          pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the tag", "brief" => "Send it", "summary" => "Sends the tag" })

          assert_equal "Sends the tag\n\n#{CodeChange::CI_WARNING}\n\n**Verified**\n- `yaml .github/workflows/release.yml` passed.\n\n" \
                       "**Checks that did not pass**\n- `actionlint .github/workflows/release.yml` failed.\n\n**Found in review**\n- No test covers the new input.\n\n" \
                       "**Open questions**\n- That the provider reads the tag.\n\n**Files**\n- `.github/workflows/release.yml` (+1 -1)\n\n#{CodeWriteUp::FOOTER}", body
        end

        test "a review that cannot run opens the change saying nothing was checked" do
          FirefightAi::ChangeReviewer.any_instance.stubs(:review).raises(FirefightAi::TransientError.new(reason: "Timeout"))
          stub_run("stdout" => agent_output, "timed_out" => false)
          body = nil
          GithubApp.expects(:open_pull_request).with { |*, **options| body = options[:body] }.returns("html_url" => "https://github.com/acme/api/pull/7")

          text = @pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })

          assert body.start_with?("Fix\n\n**Open questions**\n- Halon's review could not run"), body
          assert_includes text, "Open questions:\n- Halon's review could not run"
        end

        test "a question nobody answered in time ends the change with the question, and the step shows it" do
          heard = []
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
                                           place: @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: workspace_memberships(:alice_workspace_one),
                                                                                    max_turns: 10, max_spend_cents: 50))
          pack = Github.new(@integration, box_key: "investigation-1", request: request, progress: ->(update) { heard << update.to_h.deep_dup })
          CodeReading.any_instance.expects(:exec).with do |*, argv:, on_output: nil, **|
            next false unless argv[2] == Fixing::RUN

            session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
            ask_question!(session, "Should the job send the tag or the commit?").update_columns(options: nil, recommended: nil)
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

        test "an answer changed after the agent finished without reading it sends the change back with the new answer before the review" do
          heard = []
          alice = workspace_memberships(:alice_workspace_one)
          request = CodeAgent::Request.new(principal: alice, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
          pack = Github.new(@integration, box_key: "chat-1", request: request, progress: ->(update) { heard << update.to_h.deep_dup })
          runs = []
          CodeReading.any_instance.expects(:exec).twice.with do |*, argv:, on_output: nil, **|
            next false unless argv[2] == Fixing::RUN

            runs << [ argv[4], argv[6] ]
            if runs.one?
              session = CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api")
              question = ask_question!(session, "Tag or commit?")
              question.answer_as_halon!("The tag.", option: 0)
              on_output.call("")
              assert CodeAgentQuestionService.change!(question, nil, by: alice, option: 1).ok
              question.update_columns(message_channel_id: "C9", message_id: "5.6")
            end
            true
          end.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.expects(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/7")

          assert_enqueued_with(job: CodeAgentQuestionJob) do
            pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Send the commit", "brief" => "Send the commit" })
          end

          assert_includes runs.last[0], "The person changed their answer to your question \"Tag or commit?\". This replaces the earlier answer. Alice Smith chose: Send the commit."
          assert_equal CHANGED, runs.last[1], "the correction starts from the change it finished"
          assert_empty CodeAgentQuestion.correction_waiting.where(workspace: @workspace)
          shown = Chat::CodeFixProgress.from_h(heard.last).question
          assert_equal [ "Send the commit", "Alice Smith" ], shown.values_at("changedTo", "changedBy")
          assert_includes Chat::CodeFixProgress.from_h(heard.last).lines.map(&:text), "Sent the change back to the coding agent with the changed answer"
        end

        test "an answer changed as the push opens stops the change rather than pushing one built on the earlier answer" do
          alice = workspace_memberships(:alice_workspace_one)
          request = CodeAgent::Request.new(principal: alice, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
          pack = Github.new(@integration, box_key: "chat-1", request: request)
          question = nil
          CodeReading.any_instance.expects(:exec).with do |*, argv:, **|
            next false unless argv[2] == Fixing::RUN

            question = ask_question!(CodeAgentSession.find_by!(workspace: @workspace, repository: "acme/api"), "Tag or commit?")
            question.answer_as_halon!("The tag.", option: 0)
          end.returns("stdout" => agent_output, "timed_out" => false)
          CodeAgentSession.any_instance.stubs(:open_push!).with { question.change_answer!(nil, by: alice, option: 1) }.returns("push-token")
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never
          GithubApp.expects(:open_pull_request).never

          error = assert_raises(Integrations::Error) do
            pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          assert_equal "An answer to the coding agent's question changed as the change was pushed, so nothing was pushed. Ask again to write it with the new answer.", error.message
        end

        test "a change that reaches its spending limit pauses: its work is saved to its branch, nothing opens, and the person is asked" do
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
                                           place: conversation, tool_call_id: "call_1")
          pack = Github.new(@integration, box_key: "chat-1", request: request)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && spend_all! }
                     .returns("stdout" => agent_output(exit: 1, session: "ses_abc"), "timed_out" => false)
          pushed = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH && (pushed = argv) }.returns("stdout" => PUSHED)
          GithubApp.expects(:open_pull_request).never
          FirefightAi::ChangeReviewer.any_instance.expects(:review).never

          said = nil
          assert_enqueued_with(job: CodeAgentPauseJob) do
            said = pack.fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end

          pause = CodeAgentSession::Pause.find_by!(workspace: @workspace)
          assert_match "reached its spending limit before finishing, so it is paused. Its work so far is saved on #{pause.saved_branch}", said
          assert pause.saved_branch.start_with?(Fixing::BRANCH_PREFIX)
          assert_equal [ pause.saved_branch, "", pause.saved_branch ], pushed.values_at(5, 6, 7), "pushed to a new branch of its own"
          assert_equal [ CHANGED, NEWEST, "ses_abc", "chat-1", CodeAgentSession::DEFAULT_BUDGET_MICROS, "main" ],
                       pause.values_at(:saved_commit, :copy_ref, :agent_session_id, :box_key, :budget_micros, :base)
          assert_equal({ "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" }, pause.arguments)
          assert_in_delta CodeAgentSession::Pause::RESUMABLE_FOR.from_now, pause.resumable_until, 5.seconds
          assert_nil pause.target_branch
        end

        test "a change for an open pull request that pauses is saved beside it, never on the pull request's branch" do
          stub_pull(7)
          stub_branch("fix-pool")
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION, place: conversation)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && spend_all! }
                     .returns("stdout" => agent_output.sub("BASE start-sha", "BASE #{'h' * 40}"), "timed_out" => false)
          pushed = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH && (pushed = argv) }.returns("stdout" => PUSHED)
          GithubApp.expects(:write).never

          Github.new(@integration, box_key: "chat-1", request: request)
                .fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Raise", "brief" => "Raise it", "pull_request" => 7 })

          pause = CodeAgentSession::Pause.find_by!(workspace: @workspace)
          assert_equal [ pause.saved_branch, "", "fix-pool" ], pushed.values_at(5, 6, 7)
          assert_not_equal "fix-pool", pause.saved_branch
          assert_equal [ "fix-pool", "h" * 40 ], pause.values_at(:target_branch, :target_sha)
        end

        test "Continue while the box is still there carries on the same agent session in the same copy, with a new budget of the same size" do
          pause = paused_change(box: true)
          sent = nil
          CodeReading.any_instance.expects(:exec).with { |repo, ref:, argv:, **| argv[2] == Fixing::RUN && ref == NEWEST && (sent = argv) }
                     .returns("stdout" => agent_output, "timed_out" => false)
          pushed = nil
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH && (pushed = argv) }.returns("stdout" => PUSHED)
          GithubApp.expects(:open_pull_request).with { |_repo, branch:, **| branch == pause.saved_branch }.returns("html_url" => "https://github.com/acme/api/pull/9", "number" => 9)

          continued_pack(pause).fix_code(environment_row: @row, arguments: pause.arguments.merge(Fixing::CONTINUE_ARG => pause.id))

          assert_equal [ "s" * 40, "ses_abc" ], sent.values_at(6, 11), "starts from the saved commit and resumes the agent's session"
          assert_equal Fixing::CONTINUE_IN_PLACE, sent[4]
          assert_equal [ pause.saved_branch, "s" * 40 ], pushed.values_at(5, 6), "moves the saved branch on from what it saved"
          assert_equal 3_000_000, CodeAgentSession.where(workspace: @workspace).order(:created_at).last.budget_micros
        end

        test "Continue after the box is gone starts again from the saved branch with a handover of what was asked, answered and done" do
          pause = paused_change(box: false)
          sent = nil
          CodeReading.any_instance.expects(:exec).with { |repo, ref:, argv:, **| argv[2] == Fixing::RUN && ref == "s" * 40 && (sent = argv) }
                     .returns("stdout" => agent_output, "timed_out" => false)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.returns("stdout" => PUSHED)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/9", "number" => 9)

          continued_pack(pause).fix_code(environment_row: @row, arguments: pause.arguments.merge(Fixing::CONTINUE_ARG => pause.id))

          assert_equal [ "", "" ], sent.values_at(6, 11), "a fresh agent, nothing to resume"
          assert_includes sent[4], "You are continuing a change an earlier session started and could not finish"
          assert_includes sent[4], "What it already changed is committed on #{pause.saved_branch}"
          assert_includes sent[4], "Tag or commit? Bob Jones chose: Send the tag."
          assert_includes sent[4], "Restore the pool size", "the original request travels with it"
        end

        test "a paused change that would save a kept path refuses before anything is pushed" do
          @integration.protect_paths!([ ".github/workflows/" ])
          request = CodeAgent::Request.new(principal: workspace_memberships(:alice_workspace_one), source: AbilityGateway::SOURCE_CONVERSATION,
                                           place: conversation, tool_call_id: "call_1")
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN && spend_all! }
                     .returns("stdout" => agent_output(path: ".github/workflows/release.yml"), "timed_out" => false)
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::PUSH }.never

          assert_raises(PolicyRefusal) do
            Github.new(@integration, box_key: "chat-1", request: request).fix_code(environment_row: @row, arguments: { "repo" => "acme/api", "title" => "Fix", "brief" => "Fix it" })
          end
          assert_not CodeAgentSession::Pause.exists?(workspace: @workspace)
        end

        test "a continued pause is carried on once, and a second call naming it, or one with nobody asking, runs nothing" do
          pause = paused_change(box: false)
          CodeReading.any_instance.expects(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN }.once.returns("stdout" => agent_output, "timed_out" => false)
          GithubApp.stubs(:open_pull_request).returns("html_url" => "https://github.com/acme/api/pull/9", "number" => 9)
          arguments = pause.arguments.merge(Fixing::CONTINUE_ARG => pause.id)

          continued_pack(pause).fix_code(environment_row: @row, arguments: arguments)

          error = assert_raises(Integrations::Error) { continued_pack(pause).fix_code(environment_row: @row, arguments: arguments) }
          assert_equal "This paused change was already carried on.", error.message
          error = assert_raises(Integrations::Error) { Github.new(@integration, box_key: "chat-1").fix_code(environment_row: @row, arguments: arguments) }
          assert_equal "This paused change cannot be continued now.", error.message
        end

        test "a pause nobody pressed Continue on is never carried on, whatever the arguments say" do
          pause = paused_change(box: true)
          pause.update_columns(status: CodeAgentSession::Pause::STATUS_OFFERED)
          CodeReading.any_instance.expects(:exec).never

          error = assert_raises(Integrations::Error) do
            continued_pack(pause).fix_code(environment_row: @row, arguments: pause.arguments.merge(Fixing::CONTINUE_ARG => pause.id))
          end
          assert_equal "This paused change cannot be continued now.", error.message
        end

        test "Stop deletes the saved branch and closes the box" do
          pause = paused_change(box: true)
          pause.update_columns(status: CodeAgentSession::Pause::STATUS_OFFERED)
          GithubApp.expects(:write).with(:delete, "/repos/acme/api/git/refs/heads/halon/fix-saved", token: "ghs_token").returns({})
          WorkspaceAdapter.stubs(:for).returns(stub(update_code_pause: { success: true }))

          assert_nil CodeAgentPauseService.stop!(pause, by: workspace_memberships(:bob_workspace_one))

          assert pause.reload.stopped?
          assert_not CodeBox.live.exists?(key: "chat-1")
        end

        private

        def conversation
          @conversation ||= @workspace.conversations.create!(kind: Conversation::KIND_PERSONAL, started_by: workspace_memberships(:alice_workspace_one),
                                                              max_turns: 10, max_spend_cents: 50)
        end

        def spend_all!
          CodeAgentSession.where(workspace: @workspace, closed_at: nil).update_all(spent_micros: CodeAgentSession::DEFAULT_BUDGET_MICROS)
          true
        end

        # A change that paused with its work saved on halon/fix-saved at s..., and Continue pressed by the person it runs as.
        def paused_change(box:)
          bob = workspace_memberships(:bob_workspace_one)
          request = CodeAgent::Request.new(principal: bob, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation, tool_call_id: "call_1")
          session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic"),
                                            repository: "acme/api", request: request, box_key: "chat-1")
          session.update_columns(integration_environment_id: @row.id)
          question = ask_question!(session, "Tag or commit?")
          question.choose!(0, by: bob)
          if box
            CodeBox.create!(workspace: @workspace, key: "chat-1", address: "http://box", box_ref: "box-1", provider: "docker", secret: "s", last_used_at: Time.current)
          end
          CodeAgentSession::Pause.create!(
            session: session, workspace: @workspace, conversation: conversation, status: CodeAgentSession::Pause::STATUS_CONTINUING,
            arguments: { "repo" => "acme/api", "title" => "Restore the pool size", "brief" => "Restore the pool size to 10" }, repository: "acme/api",
            base: "main", saved_branch: "halon/fix-saved", saved_commit: "s" * 40, copy_ref: NEWEST, agent_session_id: "ses_abc", box_key: "chat-1",
            budget_micros: 3_000_000, resumable_until: 10.minutes.from_now
          )
        end

        def continued_pack(pause)
          request = CodeAgent::Request.new(principal: pause.session.principal, source: AbilityGateway::SOURCE_CONVERSATION, place: conversation)
          Github.new(@integration, box_key: "chat-1", request: request)
        end

        def pull(number, overrides = {})
          { "number" => number, "state" => "open", "merged_at" => nil, "html_url" => "https://github.com/acme/api/pull/#{number}",
            "head" => { "ref" => "fix-pool", "sha" => "h" * 40, "repo" => { "full_name" => "acme/api" } }, "base" => { "ref" => "main" } }.merge(overrides)
        end

        def stub_pull(number, overrides = {})
          GithubApp.stubs(:get).with("/repos/acme/api/pulls/#{number}", token: "ghs_token").returns(pull(number, overrides))
        end

        def stub_branch(name, protected: false, rules: [])
          GithubApp.stubs(:get).with("/repos/acme/api/branches/#{name}", token: "ghs_token").returns("protected" => protected, "commit" => { "sha" => "h" * 40 })
          GithubApp.stubs(:get).with("/repos/acme/api/rules/branches/#{name}?per_page=100", token: "ghs_token").returns(rules)
        end

        def agent_output(path: "config/database.yml", exit: 0, checks: "", patch: "diff --git a/#{path} b/#{path}\n-pool: 2\n+pool: 10\n", session: "")
          "AGENT_EXIT #{exit}\nBASE start-sha\nSESSION #{session}\nFROM start-sha\n#{checks}CHANGE #{CHANGED}\nCOUNT\t1\t1\t#{Base64.strict_encode64(path)}\n" \
            "TOUCHED\t#{Base64.strict_encode64(path)}\nBYTES\t40\nPATCH\t#{Base64.strict_encode64(patch)}\nLOG\ndone"
        end

        # What the sandbox answers for the agent's run, the push answering as it pushed.
        def stub_run(answer)
          CodeReading.any_instance.stubs(:exec).with { |*, argv:, **| argv[2] == Fixing::RUN }.returns(answer)
        end

        # What GitHub says the push changed, against the base or, with from, against another commit.
        def stub_compare(paths, from: nil)
          GithubApp.stubs(:get).with { |path, **| path.start_with?("/repos/acme/api/compare/#{"#{from}..." if from}") }
                   .returns("files" => paths.map { |path| { "filename" => path } })
        end

        def check_line(name, code, output = "")
          "CHECK\t#{Base64.strict_encode64(name)}\t#{code}\t#{Base64.strict_encode64(output)}\n"
        end

        def review(right: true, findings: [], verified: [], unverified: [], unreviewed: [])
          FirefightAi::ChangeReviewer::Review.new(right: right, findings: findings, verified: verified, unverified: unverified, unreviewed: unreviewed,
                                                  summary: "Sets the pool to 10.")
        end
      end
    end
  end
end
