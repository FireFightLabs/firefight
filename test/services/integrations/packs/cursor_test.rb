require "test_helper"

module Integrations
  module Packs
    class CursorTest < ActiveSupport::TestCase
      ARGUMENTS = { "repo" => "acme/web", "title" => "Stop the checkout timeout", "brief" => "Checkout times out after the deploy.", "base" => "release" }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "cursor", name: "Cursor")
        @row = @integration.integration_environments.create!
        Cursor.store_credentials!(@row, Cursor::API_KEY => "crsr_key")
        @reports = []
        @pack = Cursor.new(@integration, progress: ->(text) { @reports << text })
        @pack.stubs(:pause)
      end

      test "a change is an agent on the repository's address from the map, which opens the pull request itself" do
        github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
        ResourceMap.record!(github.integration_environments.create!(base_config: { "installation_id" => "1" }), ResourceMap::Snapshot.new(resources: [
          ResourceMap::Found.new(provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web", name: "acme/web",
                                 url: "https://github.com/acme/web")
        ]))
        CursorApi.any_instance.expects(:create_agent).with do |body|
          body["repos"] == [ { "url" => "https://github.com/acme/web", "startingRef" => "release" } ] && body["autoCreatePR"] == true &&
            body["name"] == "Stop the checkout timeout" && body.dig("prompt", "text").include?("Open the change as one pull request into release")
        end.returns("agent" => { "id" => "bc-1", "url" => "https://cursor.com/agents/bc-1" }, "run" => { "id" => "run-1", "status" => "CREATING" })
        CursorApi.any_instance.stubs(:run).with("bc-1", "run-1").returns(cursor_run("RUNNING"))
                 .then.returns(cursor_run("FINISHED", result: "Raised the timeout.", pr: "https://github.com/acme/web/pull/3"))
        CursorApi.any_instance.stubs(:usage).returns("totalUsage" => { "totalTokens" => 76_390 })

        text = @pack.fix_code(environment_row: @row, arguments: ARGUMENTS)["content"].first["text"]

        assert text.start_with?("Cursor opened https://github.com/acme/web/pull/3 for acme/web.\nWhat Cursor said: Raised the timeout.\nIt used 76,390 tokens.")
        assert_includes @reports, "Cursor is writing the change in session bc-1. Follow it at https://cursor.com/agents/bc-1."
      end

      test "a repository that is not on the map has to be named by its address, which is never pieced together" do
        CursorApi.any_instance.expects(:create_agent).never

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }
        assert_equal "Cursor needs the repository's address, and acme/web is not on the resource map. Give repo as the address its code host shows.", error.message
      end

      test "a repository two code hosts both hold is two repositories, so its address has to be given" do
        %w[github gitlab].each do |host|
          connection = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: host, name: host.capitalize, slug: host)
          ResourceMap.record!(connection.integration_environments.create!(base_config: { "installation_id" => "1" }), ResourceMap::Snapshot.new(resources: [
            ResourceMap::Found.new(provider: host, account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/web", name: "acme/web",
                                   url: "https://#{host}.com/acme/web")
          ]))
        end
        CursorApi.any_instance.expects(:create_agent).never

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS) }

        assert_equal "acme/web is on the map from GitHub and GitLab. Give repo as the address of the one to change.", error.message
      end

      test "a run that finished without a pull request is read again before it counts, and a cancelled one says so" do
        CursorApi.any_instance.stubs(:create_agent).returns("agent" => { "id" => "bc-1", "url" => "https://cursor.com/agents/bc-1" }, "run" => { "id" => "run-1" })
        CursorApi.any_instance.expects(:run).times(Cursor::PULL_REQUEST_GRACE + 1).returns(cursor_run("FINISHED", result: "Nothing to change."))
        CursorApi.any_instance.stubs(:usage).raises(CursorApi::Error.new("Cursor answered 500: down"))

        error = assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS.merge("repo" => "https://github.com/acme/web")) }
        assert_equal "Cursor finished without opening a pull request.\nWhat Cursor said: Nothing to change.\nFollow it at https://cursor.com/agents/bc-1.", error.message

        CursorApi.any_instance.stubs(:run).returns(cursor_run("CANCELLED"))
        assert_match "Cursor stopped without opening a pull request: its run was cancelled.",
                     assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS.merge("repo" => "https://github.com/acme/web")) }.message
      end

      test "the limit cancels the run" do
        CursorApi.any_instance.stubs(:create_agent).returns("agent" => { "id" => "bc-1", "url" => "https://cursor.com/agents/bc-1" }, "run" => { "id" => "run-1" })
        CursorApi.any_instance.stubs(:run).returns(cursor_run("RUNNING"))
        CursorApi.any_instance.expects(:cancel).with("bc-1", "run-1")
        @pack.stubs(:clock).returns(0, CodingAgent::TIME_LIMIT.to_i + 1)

        assert_raises(NativePack::Error) { @pack.fix_code(environment_row: @row, arguments: ARGUMENTS.merge("repo" => "https://github.com/acme/web")) }
      end

      test "session_status reads the agent's latest run" do
        CursorApi.any_instance.stubs(:agent).with("bc-1").returns("id" => "bc-1", "url" => "https://cursor.com/agents/bc-1", "latestRunId" => "run-2")
        CursorApi.any_instance.stubs(:run).with("bc-1", "run-2").returns(cursor_run("ERROR", result: "Could not clone."))
        CursorApi.any_instance.stubs(:usage).returns({})

        text = @pack.session_status(environment_row: @row, arguments: { "session" => "bc-1" })["content"].first["text"]

        assert text.start_with?("Cursor session bc-1: stopped (its run ended with an error)\nWhat Cursor said: Could not clone.")
        assert_match %r{Open this in Cursor, and give the person this link with what you found: https://cursor.com/agents/bc-1\z}, text
      end

      test "the key is checked against Cursor before it is saved, and by the health check" do
        CursorApi.any_instance.stubs(:me).returns("apiKeyName" => "Firefight")
        assert_nil Cursor.credential_refusal({ Cursor::API_KEY => "crsr_key" })
        assert_equal "Paste an API key.", Cursor.credential_refusal({ Cursor::API_KEY => " " })

        CursorApi.any_instance.stubs(:me).raises(CursorApi::Unauthorized.new("Cursor answered 401: Invalid API key"))
        assert_equal "Cursor refused this key: Cursor answered 401: Invalid API key.", Cursor.credential_refusal({ Cursor::API_KEY => "crsr_key" })
        assert_raises(NativePack::Error) { @pack.check_health!(@row) }
      end

      private

      def cursor_run(status, result: nil, pr: nil)
        { "id" => "run-1", "agentId" => "bc-1", "status" => status, "result" => result,
          "git" => { "branches" => [ { "repoUrl" => "github.com/acme/web", "branch" => "cursor/fix", "prUrl" => pr }.compact ] } }
      end
    end
  end
end
