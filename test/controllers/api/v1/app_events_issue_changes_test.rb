require "test_helper"

# Linear's app is sent every installed organization's Issues data change events at the app wide address, signed with
# INTEGRATION_LINEAR_WEBHOOK_SECRET, and each reaches the workspace whose chosen tracker is the connection made through
# that organization, with nothing pasted.
class Api::V1::AppEventsIssueChangesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  URL = "https://linear.app/acme/issue/ENG-12/rotate".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @app = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", slug: "linear_issue_sync", settings: {})
    @app.integration_environments.create!.store_installation!("org-1")
    LINEAR_TOOLS.each { |tool| @app.tools.create!(name: tool, description: tool, read_only: READS.include?(tool), enabled: true, params_schema: {}) }
    Integrations::Packs::Linear.any_instance.expects(:register_issue_webhook).never
    sync_with!(@workspace, @app, secret: "")
    incident = Incident.create!(
      workspace: @workspace, declared_by: @alice, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:critical_ws1), name: "Database down", is_private: false, channel_id: "C_ISSUES", source: Incident::SOURCE_SLACK
    )
    @item = incident.incident_actions.create!(created_by: @alice, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP, description: "Rotate the database password",
                                              status: IncidentAction::STATUS_OPEN, external_key: "ENG-12", external_url: URL, issue_integration: @app,
                                              issue_sync_state: IncidentAction::ISSUE_LINKED, message_ts: "1700000000.000100")
    stub_update_message
    @previous = ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"]
    ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = "app-secret"
  end

  teardown { ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = @previous }

  # A data change event as linear.app/developers/webhooks documents it.
  def change(key: "ENG-12", organization: "org-1")
    { "action" => "update", "type" => "Issue", "organizationId" => organization, "webhookId" => "app-webhook", "url" => URL,
      "createdAt" => Time.current.utc.iso8601(3), "actor" => { "id" => "user-1", "type" => "user", "name" => "Alice" },
      "updatedFrom" => { "title" => "Rotate the database password" },
      "data" => { "identifier" => key, "title" => "Rotate the replica password", "url" => URL, "updatedAt" => Time.current.utc.iso8601(3),
                  "state" => { "type" => "started" } } }
  end

  def deliver(payload, secret: "app-secret")
    body, headers = linear_delivery(payload, secret: secret)
    post api_v1_app_events_path("linear"), params: body, headers: headers
  end

  test "a change to a linked issue reaches the workspace through the app and is applied to its item" do
    assert_enqueued_jobs(1, only: IssueChangeJob) { deliver(change) }
    assert_response :ok

    perform_enqueued_jobs(only: IssueChangeJob)

    assert_equal "Rotate the replica password", @item.reload.description
  end

  test "the setting asks for nothing, and says nothing is missing" do
    assert Integrations::Issues.through_app?(@app)
    assert_nil @workspace.reload.issue_webhook_blocked_reason
    settings = WorkspaceSettingsSerializer.one(@workspace).as_json
    assert_equal [ true, false ], settings.values_at("issueWebhookThroughApp", "issueWebhookAutomatic")
  end

  test "a change to an issue no item is linked to, from another organization, or about something else is taken and left alone" do
    assert_no_enqueued_jobs(only: IssueChangeJob) do
      deliver(change(key: "ENG-99"))
      deliver(change(organization: "org-elsewhere"))
      deliver(change.merge("type" => "Comment", "data" => { "id" => "comment-1", "body" => "Looking", "issueId" => "issue-1" }))
    end
    assert_response :ok
  end

  test "a workspace that chose another tracker, or one whose connection was made through Linear's MCP server, gets nothing through the app" do
    mcp = connect_tracker!(@workspace, provider: "linear", slug: "linear_mcp", name: "Linear MCP")
    sync_with!(@workspace, mcp)

    assert_no_enqueued_jobs(only: IssueChangeJob) { deliver(change) }
  end

  test "a delivery the app did not sign is refused" do
    assert_no_enqueued_jobs(only: IssueChangeJob) { deliver(change, secret: "someone else's") }

    assert_response :unauthorized
  end
end
