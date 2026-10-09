require "test_helper"

module Integrations
  # The fixtures are what OpenCode 1.18.34 printed for real, run with a scripted model, with the copy's path set to where
  # the sandbox keeps it.
  class SandboxAgentEventsTest < ActiveSupport::TestCase
    test "each thing the agent did is one short line, with what it changed and the tests it ran" do
      work = read("fix_run")

      assert_equal [
        "Thinking: I'll start by reading the database config.",
        "Read config/database.yml",
        "Searched for 'pool' in *.yml files",
        "Looked for files matching 'test/**/*_test.rb'",
        "Thinking: The pool is 2, it should be 10.",
        "Edited config/database.yml",
        "Created test/pool_test.rb",
        "Ran ruby test/pool_test.rb",
        "Ran ruby -e 'exit 3' && echo DATABASE_URL=[REDACTED:credential_url]db.internal:5432/app",
        "Edited config/missing.yml",
        "Updated its plan",
        "Tried a tool it does not have",
        "Ran git status --short",
        "Thinking: I set the pool back to 10 in config/database.yml and added a test, which passes."
      ], work.lines.map(&:text)
      assert_equal [ nil, nil, nil, nil, nil, nil, nil, "passed", "failed", "failed", nil, "failed", nil, nil ], work.lines.map(&:result)
      assert_equal [ "config/database.yml", "test/pool_test.rb" ], work.changed, "an edit that failed changed nothing"
      assert_equal [ [ "ruby test/pool_test.rb", true ] ], work.tests.map { |test| [ test.command, test.passed ] }
      assert work.live?
      assert_equal 14, work.total
    end

    test "a patch names every file it touched, a failing spec run fails, and a provider's refusal stops it with its words" do
      work = read("patch_run_then_error")

      assert_equal [ "Thinking: Patching the readme.", "Edited 2 files", "Ran cd . && bundle exec rspec spec/missing_spec.rb",
                     "Tried a tool it does not have", "Tried a tool it does not have", "Stopped: Budget spent" ], work.lines.map(&:text)
      assert_equal [ "README.md", "docs/pool.md" ], work.changed
      assert_equal [ [ "cd . && bundle exec rspec spec/missing_spec.rb", false ] ], work.tests.map { |test| [ test.command, test.passed ] }
      assert_equal "failed", work.lines.last.result
    end

    test "no file's content or a tool's output is ever kept" do
      kept = read("fix_run").to_h.to_json

      refute_includes kept, "pool: 2"
      refute_includes kept, "assert_includes"
      refute_includes kept, "hunter2"
      refute_includes kept, "/runs/"
    end

    test "secrets in a command are redacted, by pattern and by a name that says it is secret" do
      work = Chat::CodeFixProgress.start
      events = SandboxAgentEvents.new(work)

      events.read(tool_use("bash", { "command" => "API_TOKEN=abc123 GITHUB_TOKEN=ghp_#{'a' * 36} bin/rails test" }, exit_code: 0))

      assert_equal "Ran API_TOKEN=[REDACTED] GITHUB_TOKEN=[REDACTED] bin/rails test", work.lines.last.text
      assert_equal [ true ], work.tests.map(&:passed), "a command that starts with settings still runs tests"
    end

    test "what must never show, such as the agent's own token, is hidden wherever the agent prints it" do
      work = Chat::CodeFixProgress.start
      events = SandboxAgentEvents.new(work, hidden: [ "cas_token123" ])

      events.read([ tool_use("bash", { "command" => "curl -H 'Authorization: Bearer cas_token123' https://ff.example.com" }, exit_code: 0),
                    "#{{ type: 'error', error: { name: 'APIError', data: { message: 'cas_token123 is spent' } } }.to_json}\n" ].join)

      assert_equal [ "Ran curl -H 'Authorization: Bearer [REDACTED]' https://ff.example.com", "Stopped: [REDACTED] is spent" ], work.lines.map(&:text)
    end

    test "tools it reaches through Firefight and its helpers read as plain lines, and an unknown one by its name" do
      work = Chat::CodeFixProgress.start
      events = SandboxAgentEvents.new(work)

      events.read([ tool_use("firefight_search_web", { "query" => "rails pool size" }), tool_use("firefight_read_web_page", { "url" => "https://guides.rubyonrails.org" }),
                    tool_use("task", { "description" => "Find callers" }), tool_use("something_new", {}) ].join)

      assert_equal [ "Searched the web for 'rails pool size'", "Read https://guides.rubyonrails.org", "Handed 'Find callers' to a helper",
                     "Used something_new" ], work.lines.map(&:text)
    end

    test "a piece of a line, prose with code in it, and output that is not an event are passed over or cut down" do
      work = Chat::CodeFixProgress.start
      events = SandboxAgentEvents.new(work)

      events.read("ssion\":\"x\"}}\nnot json\n#{{ type: 'text', part: { text: "Here is the fix. ```ruby\nputs 1\n``` Done." } }.to_json}\n")

      assert_equal [ "Thinking: Here is the fix." ], work.lines.map(&:text)
    end

    test "which commands count as running tests" do
      events = SandboxAgentEvents.new(Chat::CodeFixProgress.start)

      [ "bin/rails test test/x_test.rb", "bundle exec rspec", "npm test", "npm run test -- --watch=false", "go test ./...", "pytest -q",
        "python -m pytest", "cd api && yarn test", "RAILS_ENV=test bin/rails test", "npx vitest run", "cargo test", "ruby -Itest test/x_test.rb" ].each do |command|
        assert events.send(:test_command?, command), command
      end
      [ "git diff test/x_test.rb", "cat spec/x_spec.rb", "ls test", "bundle install" ].each do |command|
        refute events.send(:test_command?, command), command
      end
    end

    test "a provider's error stops it with one plain line, never the headers and body it came with" do
      work = Chat::CodeFixProgress.start
      events = SandboxAgentEvents.new(work)
      events.read("#{api_error.to_json}\n")

      assert_equal "Stopped: Too many requests, try again later", work.lines.last.text
      assert_equal "Too many requests, try again later", events.stop_reason("")
      refute_match "cf-ray", work.lines.last.text
    end

    test "the last words and why it stopped are read from the log when nothing was heard as it ran" do
      log = [ "tail of a line cut short\"}", { type: "text", part: { text: "I set the pool to 10.\n\nCould not run here:\n- the tests, since no database was there" } }.to_json,
              api_error.to_json ].join("\n")
      events = SandboxAgentEvents.new(Chat::CodeFixProgress.start)

      assert_equal "I set the pool to 10.\n\nCould not run here:\n- the tests, since no database was there", events.last_words(log)
      assert_equal "Too many requests, try again later", events.stop_reason(log)
      assert_nil events.last_words("not an event"), "a log with no words says nothing rather than itself"
    end

    test "what the agent's summary lists under Could not run here is each line, however it marks the heading" do
      events = SandboxAgentEvents.new(Chat::CodeFixProgress.start)
      said = lambda do |text|
        events.could_not_run({ type: "text", part: { text: text } }.to_json)
      end

      assert_equal [ "`bin/rails test test/models/pool_test.rb`, since no database was there", "eslint, since node_modules was not installed" ],
                   said.call("Sets the pool.\n\n**Could not run here:**\n- `bin/rails test test/models/pool_test.rb`, since no database was there\n" \
                             "* eslint, since node_modules was not installed\n\nOpen questions: none")
      assert_equal [ "the integration tests, which need Redis" ], said.call("## Could not run here\n\n1. the integration tests, which need Redis")
      assert_equal [ "the suite, which needs DATABASE_URL=[REDACTED:credential_url]db/app" ],
                   said.call("Could not run here: the suite, which needs DATABASE_URL=postgres://app:s3cret@db/app")
      assert_empty said.call("Could not run here: none")
      assert_empty said.call("Everything ran and passed.")
    end

    private

    # What OpenCode prints for a provider's refusal: the message, and the answer's headers and body.
    def api_error
      { type: "error", error: { name: "APIError", data: { message: "Too many requests; try again later.\nretry-after: 30", statusCode: 429,
                                                          responseHeaders: { "cf-ray" => "8f1", "retry-after" => "30" }, responseBody: "{\"error\":\"rate\"}" } } }
    end

    def read(name)
      work = Chat::CodeFixProgress.start
      SandboxAgentEvents.new(work).read(file_fixture("opencode/#{name}.jsonl").read)
    end

    def tool_use(tool, input, exit_code: nil)
      state = { status: "completed", input: input, output: "", title: "", metadata: { exit: exit_code }.compact }
      "#{{ type: 'tool_use', part: { type: 'tool', tool: tool, state: state } }.to_json}\n"
    end
  end
end
