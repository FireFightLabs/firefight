require "test_helper"

# A connection made with Firefight's own app has its webhook registered by Firefight, and taken back with it.
class IssueWebhookRegistrationTest < ActiveSupport::TestCase
  include IssueTrackerTestHelper

  TARGET = { "site" => "acme.atlassian.net", "project" => "OPS" }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @app = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "jira", name: "Jira issue sync", slug: "jira_issue_sync",
                                           settings: { Integration::APP_SETTING => true })
    @app.integration_environments.create!
    IssueTrackerTestHelper::JIRA_TOOLS.each do |tool|
      @app.tools.create!(name: tool, description: tool, read_only: IssueTrackerTestHelper::READS.include?(tool), enabled: false, params_schema: {})
    end
    @service = IssueSyncService.new(@workspace)
    ENV["APP_HOST"], @host = "ff.example.com", ENV["APP_HOST"]
  end

  teardown { ENV["APP_HOST"] = @host }

  def choose(integration, target: TARGET)
    @service.update_settings!({ issue_tracker: integration&.slug, issue_tracker_target: target,
                                issue_creation: integration ? Workspace::IssueSync::ISSUE_CREATION_ASKED : Workspace::IssueSync::ISSUE_CREATION_NEVER }, by: @alice)
    @workspace.reload
  end

  test "choosing the app connection registers its webhook at the workspace's address and ledgers it as the admin" do
    Integrations::Packs::Jira.any_instance.expects(:register_issue_webhook)
                             .with { |_row, url:, target:| url == "https://ff.example.com/api/v1/issue_events/#{@workspace.reload.issue_webhook_token}" && target == TARGET }
                             .returns(Integrations::Issues::Webhook.new(id: "1000", expires_at: 30.days.from_now))

    choose(@app)

    row = @app.integration_environments.sole
    assert_equal [ "1000", nil ], [ row.issue_webhook_id, @workspace.issue_webhook_blocked_reason ]
    assert Ability::Invocation.exists?(principal_id: @alice.id, action_key: "workspace.update", source: AbilityGateway::SOURCE_ISSUE_SYNC)
    assert_nil @workspace.issue_creation_blocked_reason
  end

  test "a registration the tracker refuses is the setting's reason, and the settings are kept" do
    Integrations::Packs::Jira.any_instance.stubs(:register_issue_webhook).raises(Integrations::Issues::Failed, "Jira answered 403")

    choose(@app)

    assert_equal "jira_issue_sync", @workspace.issue_tracker
    assert_equal "Firefight could not register Jira issue sync's webhook, so changes made there do not reach it: Jira answered 403.",
                 @workspace.issue_webhook_blocked_reason
  end

  test "choosing another tracker, or none, removes the webhook and the grants, and removing the connection does too" do
    Integrations::Packs::Jira.any_instance.stubs(:register_issue_webhook).returns(Integrations::Issues::Webhook.new(id: "1000"))
    choose(@app)

    Integrations::Packs::Jira.any_instance.expects(:remove_issue_webhook).with(anything, "1000")
    choose(nil)
    assert_nil @app.integration_environments.sole.issue_webhook_id
    assert_not @workspace.ability_grants.exists?(principal: SystemAgent.issue_sync)

    choose(@app)
    Integrations::Packs::Jira.any_instance.expects(:remove_issue_webhook).with(anything, "1000")
    @service.connection_removed(@app, by: @alice)
    assert_nil @app.integration_environments.sole.issue_webhook_id
  end

  test "a connection through the MCP server registers nothing and asks for the secret instead" do
    mcp = connect_tracker!(@workspace, provider: "jira", slug: "jira")
    Integrations::Packs::Jira.any_instance.expects(:register_issue_webhook).never

    choose(mcp)

    assert_match "until its webhook's signing secret is saved", @workspace.issue_webhook_blocked_reason
  end

  test "Linear's app reaches Linear's MCP server, registers nothing, and asks for nothing once it acts as the app" do
    linear = connect_tracker!(@workspace, provider: "linear", slug: "linear")
    linear.update!(settings: linear.settings.merge(Integration::APP_SETTING => true))
    linear.integration_environments.sole.store_installation!("org-1")

    choose(linear, target: { "team" => "ENG" })

    assert_not Integrations::Issues.registers_webhooks?(linear)
    assert_nil @workspace.issue_webhook_blocked_reason
  end

  test "a webhook close to lapsing is refreshed, and one the tracker will not refresh is the reason" do
    row = @app.integration_environments.sole
    row.update!(issue_webhook_id: "1000", issue_webhook_expires_at: 2.days.from_now)
    @workspace.update_columns(issue_tracker: @app.slug)
    Integrations::Packs::Jira.any_instance.stubs(:refresh_issue_webhook).with(anything, "1000").returns(Time.utc(2026, 12, 1))

    IssueWebhookRefreshJob.perform_now
    assert_equal Time.utc(2026, 12, 1), row.reload.issue_webhook_expires_at

    Integrations::Packs::Jira.any_instance.stubs(:refresh_issue_webhook).raises(Integrations::Issues::Failed, "Jira answered 403")
    row.update_columns(issue_webhook_expires_at: 1.day.from_now)
    IssueWebhookRefreshJob.perform_now
    assert_match "Jira answered 403", @workspace.reload.issue_webhook_blocked_reason
  end
end
