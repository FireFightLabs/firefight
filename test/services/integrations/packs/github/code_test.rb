require "test_helper"

module Integrations
  module Packs
    class Github
      class CodeTest < ActiveSupport::TestCase
        COMMIT = "c4e4267d46e638ac6f257d117ab448c280d01c0b".freeze

        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
          @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
          @pack = Github.new(@integration, box_key: "investigation-1")
          GithubApp.stubs(:installation_token).returns("ghs_token")
        end

        test "a search runs git grep on the commit and says the commit once, without a sensitive file" do
          box_answers(where: Sandboxes::Client::IN_GIT, argv: [ "grep", "-n", "-I", "-E", "--full-name", "-e", "require_admin", Sandboxes::Client::COMMIT, "--" ],
                      stdout: "#{COMMIT}:app/controllers/billing_controller.rb:8:    before_action :require_admin!\n#{COMMIT}:.env:1:REQUIRE_ADMIN=1\n")

          text = @pack.code_search(environment_row: @row, arguments: { "repo" => "acme/cloud", "pattern" => "require_admin" })

          assert_equal "1 matches in acme/cloud at c4e4267d46e6\napp/controllers/billing_controller.rb:8:    before_action :require_admin!", text
        end

        test "a search at a commit passes the commit to the box" do
          box_answers(ref: "b586e23", where: Sandboxes::Client::IN_GIT, argv: [ "grep", "-n", "-I", "-E", "--full-name", "-e", "x", Sandboxes::Client::COMMIT, "--", "app" ], stdout: "")

          text = @pack.code_search(environment_row: @row, arguments: { "repo" => "acme/cloud", "pattern" => "x", "ref" => "b586e23", "path_prefix" => "app" })

          assert_equal "No matches in acme/cloud at c4e4267d46e6.", text
        end

        # Seen in a real chat. The billing controller called require_admin!, which nothing defined, and Halon read past it.
        test "a name nothing defines is said to be undefined, with what frameworks make that nobody writes" do
          CodeReading.any_instance.stubs(:exec).returns(result(stdout: ""))

          text = @pack.find_definition(environment_row: @row, arguments: { "symbol" => "require_admin!", "repos" => [ "acme/cloud", "acme/app" ] })

          assert_match "require_admin! is not defined in acme/cloud, acme/app.", text
          assert_match "route helpers", text
        end

        test "a definition says where, with its kind and line, from ctags run on the name as an argument" do
          CodeReading.any_instance.expects(:exec).with do |repo, **options|
            repo == "acme/app" && options[:where] == Sandboxes::Client::IN_CHECKOUT && options[:argv].last == "require_authentication" &&
              options[:argv][0, 2] == [ "sh", "-c" ] && !options[:argv][2].include?("require_authentication")
          end.returns(result(stdout: "require_authentication\t./app/controllers/application_controller.rb\t/^  def require_authentication$/;\"\tkind:method\tline:62\n"))

          text = @pack.find_definition(environment_row: @row, arguments: { "symbol" => "require_authentication", "repos" => [ "acme/app" ] })

          assert_equal "require_authentication is defined at\nacme/app  app/controllers/application_controller.rb:62  method (at c4e4267d46e6)", text
        end

        test "without named repositories a definition is looked for in every one the connection sees" do
          GithubApp.stubs(:get).with("/installation/repositories?per_page=100", token: "ghs_token")
                   .returns("repositories" => [ { "full_name" => "acme/cloud" }, { "full_name" => "acme/app" } ])
          looked_in = []
          CodeReading.any_instance.stubs(:exec).with { |repo, **| looked_in << repo }.returns(result(stdout: ""))

          @pack.find_definition(environment_row: @row, arguments: { "symbol" => "Charge" })

          assert_equal [ "acme/cloud", "acme/app" ], looked_in
        end

        test "history asks git log for the text that was added or removed" do
          box_answers(where: Sandboxes::Client::IN_GIT, argv: [ "log", "--format=%H%x09%aI%x09%an%x09%s", "-n", "30", "-S", "def require_admin!", Sandboxes::Client::COMMIT, "--" ],
                      stdout: "#{COMMIT}\t2026-08-10T07:40:54+02:00\tUros\tPolar billing\n")

          text = @pack.git_log(environment_row: @row, arguments: { "repo" => "acme/cloud", "added_or_removed" => "def require_admin!" })

          assert_equal "1 commits in acme/cloud at c4e4267d46e6, newest first\nc4e4267d46e6  2026-08-10T07:40:54+02:00  Uros  Polar billing", text
        end

        test "a ref that looks like an option never reaches git" do
          CodeReading.any_instance.expects(:exec).never

          assert_raises(NativePack::Error) do
            @pack.show_commit(environment_row: @row, arguments: { "repo" => "acme/cloud", "sha" => "--output=/tmp/x" })
          end
        end

        test "the language server's answer comes back as paths inside the repository" do
          CodeReading.any_instance.expects(:lsp).with(
            "acme/app", method: "textDocument/definition", ref: nil, path: "app/controllers/inertia_controller.rb", line: 6, column: 19
          ).returns(
            "commit" => COMMIT, "root" => "/runs/acme__app-#{COMMIT}",
            "result" => [ { "uri" => "file:///runs/acme__app-#{COMMIT}/app/controllers/application_controller.rb", "range" => { "start" => { "line" => 61, "character" => 6 } } } ]
          )

          text = @pack.ask_language_server(environment_row: @row, arguments: {
            "repo" => "acme/app", "question" => "definition", "path" => "app/controllers/inertia_controller.rb", "line" => 6, "column" => 19
          })

          assert_equal "1 results in acme/app at c4e4267d46e6\napp/controllers/application_controller.rb:62", text
        end

        test "commands wait for the workspace's AI SRE switch" do
          CodeReading.any_instance.expects(:exec).never

          error = assert_raises(NativePack::Error) do
            @pack.run_shell(environment_row: @row, arguments: { "repo" => "acme/app", "command" => "ls" })
          end
          assert_match "not switched on", error.message
        end

        test "tests install what the repository asks for first, and say what failed" do
          FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
          CodeReading.any_instance.expects(:prepare).with("acme/app", ref: nil).returns(
            "already" => false, "prepared" => [ { "file" => "Gemfile.lock", "command" => "bundle install", "exit_code" => 0, "output" => "" } ]
          )
          CodeReading.any_instance.expects(:exec).with(
            "acme/app", ref: nil, where: Sandboxes::Client::IN_COPY, argv: [ "sh", "-c", "bin/rails test" ], services: [ "postgres" ], timeout: Code::TESTS_TIMEOUT
          ).returns(result(stdout: "1 runs, 0 failures\n", stderr: "NoMethodError: undefined method 'require_admin!'", exit_code: 1))

          text = @pack.run_tests(environment_row: @row, arguments: { "repo" => "acme/app", "command" => "bin/rails test", "services" => [ "postgres" ] })

          assert_match "bundle install (for Gemfile.lock) exited 0", text
          assert_match "exit 1", text
          assert_match "undefined method 'require_admin!'", text
        end

        test "a service that does not exist is refused before anything starts" do
          FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
          CodeReading.any_instance.expects(:prepare).never

          assert_raises(NativePack::Error) do
            @pack.run_tests(environment_row: @row, arguments: { "repo" => "acme/app", "command" => "x", "services" => [ "mysql" ] })
          end
        end

        test "a code tool called outside a run is refused rather than starting a box nobody closes" do
          pack = Github.new(@integration)

          assert_raises(Integrations::Error) do
            pack.list_files(environment_row: @row, arguments: { "repo" => "acme/app" })
          end
        end

        private

        def box_answers(argv:, where:, stdout:, ref: nil)
          CodeReading.any_instance.expects(:exec).with("acme/cloud", ref: ref, where: where, argv: argv).returns(result(stdout: stdout))
        end

        def result(stdout:, stderr: "", exit_code: 0)
          { "stdout" => stdout, "stderr" => stderr, "exit_code" => exit_code, "timed_out" => false, "truncated" => false, "commit" => COMMIT }
        end
      end
    end
  end
end
