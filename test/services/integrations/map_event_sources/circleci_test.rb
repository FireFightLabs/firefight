require "test_helper"

module Integrations
  module MapEventSources
    class CircleciTest < ActiveSupport::TestCase
      URL = "https://firefight.example/api/v1/map_events/token".freeze
      WORKFLOW_COMPLETED = {
        "id" => "3888f21b", "type" => "workflow-completed", "happened_at" => "2021-09-01T22:49:34.317Z",
        "project" => { "id" => "p-1", "name" => "webhook-service", "slug" => "github/circleci/webhook-service" },
        "workflow" => { "id" => "w-1", "name" => "build-test-deploy", "status" => "failed",
                        "url" => "https://app.circleci.com/pipelines/github/circleci/webhook-service/130/workflows/w-1" },
        "pipeline" => { "id" => "pl-1", "number" => 130, "vcs" => { "branch" => "main", "revision" => "1dc6aa69429bff4806ad6afe58d3d8f57e25973e" } }
      }.freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "circleci", name: "CircleCI")
        @row = integration.integration_environments.create!
        Packs::Circleci.store_credentials!(@row, Packs::Circleci::API_TOKEN => "CCIPAT_x")
        CircleciApi.any_instance.stubs(:collaborations).returns([ { "id" => "org-1" } ])
        CircleciApi.any_instance.stubs(:projects).returns(Pages::Read.new(items: [ { "id" => "p-1" }, { "id" => "p-2" } ], complete: true))
      end

      test "a delivery counts only with the v1 signature CircleCI documents for its secret" do
        # The example in CircleCI's guide: hello world with secret.
        signed = { "circleci-signature" => "v1=734cc62f32841568f45715aeb9f4d7891324e6d948e4c6c60c0621cdac48623a" }

        assert Circleci.verify(raw_body: "hello world", headers: signed, secret: "secret")
        assert_not Circleci.verify(raw_body: "hello world", headers: signed, secret: "other")
        assert_not Circleci.verify(raw_body: "hello world", headers: { "circleci-signature" => "v2=734cc62f" }, secret: "secret")
        assert_not Circleci.verify(raw_body: "hello world", headers: signed, secret: nil)
      end

      test "a workflow or job ending wakes watches, changes nothing on the map, and a workflow that ended is a CI run that ended" do
        headers = { "circleci-event-type" => "workflow-completed" }

        assert Circleci.wakes?(WORKFLOW_COMPLETED, headers: headers)
        assert Circleci.wakes?(WORKFLOW_COMPLETED, headers: { "circleci-event-type" => "job-completed" })
        assert_not Circleci.wakes?(WORKFLOW_COMPLETED, headers: { "circleci-event-type" => "ping" })
        assert_empty Circleci.events(WORKFLOW_COMPLETED, headers: headers)

        run = Circleci.runs_ended(WORKFLOW_COMPLETED, headers: headers).sole
        assert_equal [ RunsEnded::KIND_CI, RunsEnded::OUTCOME_FAILED, "build-test-deploy", "github/circleci/webhook-service", "main" ],
                     [ run.kind, run.outcome, run.name, run.place, run.ref ]
        assert_empty Circleci.runs_ended(WORKFLOW_COMPLETED, headers: { "circleci-event-type" => "job-completed" })
      end

      test "registering adds a webhook to each project, puts its own from before back, and keeps the secret first" do
        CircleciApi.any_instance.stubs(:webhooks).with("p-1").returns([ { "id" => "h-1", "url" => URL } ])
        CircleciApi.any_instance.stubs(:webhooks).with("p-2").returns([ { "id" => "h-9", "url" => "https://elsewhere.example/hook" } ])
        CircleciApi.any_instance.expects(:update_webhook).with("h-1", url: URL, secret: anything, events: Circleci::EVENTS)
        CircleciApi.any_instance.expects(:create_webhook).with("p-2", name: Circleci::WEBHOOK_NAME, url: URL, secret: anything, events: Circleci::EVENTS)

        webhook = Circleci.register(@row, url: URL)

        assert_equal Circleci::ALL_PROJECTS, webhook.id
        assert_equal @row.reload.map_events_secret, webhook.secret
      end

      test "a project without Firefight's webhook, or one CircleCI switched off, is registered again" do
        CircleciApi.any_instance.stubs(:webhooks).returns([ { "id" => "h-1", "url" => URL, "events" => Circleci::EVENTS, "is_enabled" => true } ])
        assert_not Circleci.register_again?(@row, url: URL)

        CircleciApi.any_instance.stubs(:webhooks).with("p-2").returns([ { "id" => "h-2", "url" => URL, "events" => Circleci::EVENTS, "is_enabled" => false } ])
        assert Circleci.register_again?(@row, url: URL)
      end

      test "a connection through CircleCI's hosted server is told live updates need an API token" do
        mcp = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "circleci", name: "CircleCI server", slug: "circleciserver",
                                  settings: { "server_url" => "https://mcp.circleci.com/v1/mcp" })

        error = assert_raises(MapEventSource::Refused) { Circleci.register(mcp.integration_environments.create!, url: URL) }
        assert_match "personal API token", error.message
      end
    end
  end
end
