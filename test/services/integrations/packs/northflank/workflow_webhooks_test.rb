require "test_helper"

module Integrations
  module Packs
    class Northflank
      class WorkflowWebhooksTest < ActiveSupport::TestCase
        TOKEN = "Xq9bNfLm2RtYvWc8KpZaH4sJdE6uGo1i".freeze

        setup do
          @workspace = workspaces(:slack_workspace_one)
          @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
          @row = @integration.integration_environments.create!
          Northflank.store_credentials!(@row, Northflank::API_TOKEN => "nf-token")
          @row.store_fields!(Northflank::PROJECT => "firefight")
          @pack = Northflank.new(@integration)
          NorthflankApi.any_instance.stubs(:services).returns(Pages::Read.new(items: [ { "id" => "web", "name" => "web", "appId" => "/firefight-labs/firefight/web" } ], complete: true))
          NorthflankApi.any_instance.stubs(:addons).returns(Pages::Read.new(items: [], complete: true))
        end

        test "a webhook trigger is added with a token Firefight makes, the whole definition sent back without read-only fields" do
          NorthflankApi.any_instance.stubs(:workflow).with("firefight", "release").returns(definition)
          sent = nil
          NorthflankApi.any_instance.expects(:update_workflow).with do |project, workflow, body|
            sent = body
            project == "firefight" && workflow == "release"
          end.returns({})

          result = @pack.call("add_workflow_webhook", environment_row: @row, arguments: { "workflow" => "release", "ref" => "release-webhook" })

          assert_equal %w[name apiVersion spec triggers], sent.keys
          added = sent["triggers"].last
          assert_equal({ "kind" => "webhook", "ref" => "release-webhook" }, added.except("spec"))
          assert_match(/\A[A-Za-z0-9]{48}\z/, added.dig("spec", "token"))
          assert_equal definition["triggers"].first, sent["triggers"].first

          text = result["content"].sole["text"]
          refute_includes text, added.dig("spec", "token")
          assert_includes text, "so a commit is passed as github.sha"
          reveal = SecretHandoffs.reveal_of(result)
          assert_equal "secret:#{@integration.id}::add_workflow_webhook:firefight/release/release-webhook", reveal["reference"]
          assert_includes text, "pass value_from #{reveal['reference']}"
        end

        test "a ref the workflow already has, or one Northflank would not read, is refused" do
          NorthflankApi.any_instance.stubs(:workflow).returns(definition)
          NorthflankApi.any_instance.expects(:update_workflow).never

          assert_raises(NativePack::Error) { @pack.call("add_workflow_webhook", environment_row: @row, arguments: { "workflow" => "release", "ref" => "github" }) }
          assert_raises(NativePack::Error) { @pack.call("add_workflow_webhook", environment_row: @row, arguments: { "workflow" => "release", "ref" => "has space" }) }
        end

        test "a reference reads the address live, only in a project the connection reaches" do
          NorthflankApi.any_instance.stubs(:workflow).with("firefight", "release").returns(definition(webhook: true))

          assert_equal "https://webhooks.northflank.com/workflows/#{TOKEN}", @pack.secret_value(environment_row: @row, path: "firefight/release/deploy-hook")
          assert_nil @pack.secret_value(environment_row: @row, path: "firefight/release/missing")
          assert_raises(NativePack::Error) { @pack.secret_value(environment_row: @row, path: "elsewhere/release/deploy-hook") }
        end

        test "reading a workflow through api_request never shows a webhook token or address" do
          NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "workflows/release", nil, {})
                       .returns("data" => definition(webhook: true).merge("description" => "calls webhooks.northflank.com/workflows/#{TOKEN}"))
          tool = Integration::Tool.new(integration: @integration, name: "api_request")

          text = NativeExecutor.call(tool: tool, environment_row: @row, arguments: { "method" => "GET", "path" => "workflows/release" })["content"].sole["text"]

          refute_includes text, TOKEN
          assert_includes text, "\"token\":\"[hidden]\""
          assert_includes text, "[REDACTED:northflank_webhook]"
        end

        test "a change sending a trigger back as it was read keeps its token, and a token written by Halon is refused" do
          NorthflankApi.any_instance.stubs(:request).with("GET", "firefight", "workflows/release").returns("data" => definition(webhook: true))
          hidden = definition(webhook: true).slice("name", "apiVersion", "spec", "triggers")
          hidden["triggers"].last["spec"]["token"] = "[hidden]"
          NorthflankApi.any_instance.expects(:request).with do |verb, _project, path, body, _query|
            verb == "POST" && path == "workflows/release" && body["triggers"].last.dig("spec", "token") == TOKEN
          end.returns("data" => {})

          @pack.call("api_request", environment_row: @row, arguments: { "method" => "POST", "path" => "workflows/release", "body" => hidden })

          written = hidden.deep_dup
          written["triggers"].last["spec"]["token"] = "made-up-token"
          error = assert_raises(PolicyRefusal) do
            @pack.call("api_request", environment_row: @row, arguments: { "method" => "POST", "path" => "workflows/release", "body" => written })
          end
          assert_includes error.message, "add_workflow_webhook"
        end

        private

        def definition(webhook: false)
          triggers = [ { "id" => "t1", "kind" => "vcs-push", "ref" => "github", "spec" => { "vcs" => { "vcsService" => "github", "repoUrl" => "https://github.com/acme/web" } } } ]
          triggers << { "id" => "t2", "kind" => "webhook", "ref" => "deploy-hook", "spec" => { "token" => TOKEN } } if webhook
          { "id" => "release", "name" => "Release", "apiVersion" => "v1.2", "spec" => { "kind" => "Workflow" }, "triggers" => triggers,
            "status" => "success", "paused" => false, "createdAt" => "2026-09-01T10:00:00Z", "updatedAt" => "2026-09-01T10:00:00Z" }
        end
      end
    end
  end
end
