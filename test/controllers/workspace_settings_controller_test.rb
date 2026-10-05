require "test_helper"

# A grant says who may ask, this screen says whether there is anything to ask for.
class WorkspaceSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "transcript access is off until somebody turns it on" do
    assert_not @workspace.transcript_access_enabled
    assert_not_nil @workspace.transcript_access_blocked_reason

    patch settings_workspace_path, params: { transcript_access_enabled: true }

    assert_redirected_to settings_workspace_path
    assert @workspace.reload.transcript_access_enabled
    assert_nil @workspace.transcript_access_blocked_reason
  end

  test "Firefight tests Halon on a workspace's rated answers only once someone turns it on" do
    assert_not @workspace.halon_regression_enabled

    patch settings_workspace_path, params: { halon_regression_enabled: true }

    assert_redirected_to settings_workspace_path
    assert @workspace.reload.halon_regression_enabled
  end

  # A blank retention is a choice, so it stores as keep forever rather than falling back to the default.
  test "clearing the retention keeps conversations for good" do
    patch settings_workspace_path, params: { transcript_retention_days: "" }

    assert_redirected_to settings_workspace_path
    assert_nil @workspace.reload.transcript_retention_days
    assert_nil @workspace.transcripts_purge_after
  end

  test "a retention window is stored in days" do
    patch settings_workspace_path, params: { transcript_retention_days: 7 }

    assert_equal 7, @workspace.reload.transcript_retention_days
    assert_equal 7.days, @workspace.transcripts_purge_after
  end

  test "a connected coding agent can be chosen to write code fixes, and Firefight's own agent chosen back" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "devin", name: "Devin", slug: "devin")

    patch settings_workspace_path, params: { code_fix_agent: "devin" }

    assert_redirected_to settings_workspace_path
    assert_equal "Workspace settings were updated.", flash[:notice]
    assert_equal "devin", @workspace.reload.code_fix_agent

    patch settings_workspace_path, params: { code_fix_agent: "" }
    assert_nil @workspace.reload.code_fix_agent
  end

  test "only a coding agent connected to the workspace can write code fixes" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")

    patch settings_workspace_path, params: { code_fix_agent: "github" }

    assert_redirected_to settings_workspace_path
    assert_nil @workspace.reload.code_fix_agent
  end

  test "the screen offers Firefight's own agent and each connected coding agent, and says when the chosen one cannot run" do
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "cursor", name: "Cursor", slug: "cursor")
    @workspace.update!(code_fix_agent: "cursor")

    get settings_workspace_path, headers: {
      "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s
    }

    settings = JSON.parse(response.body).dig("props", "settings")
    assert_equal [ { "value" => nil, "label" => "Firefight's own agent" }, { "value" => "cursor", "label" => "Cursor" } ], settings["codeFixAgents"]
    assert_equal "cursor", settings["codeFixAgent"]
    assert_equal "Cursor's fix_code tool is switched off, so code steps wait for a person. Switch it on under Integrations.", settings["codeFixAgentBlockedReason"]
  end

  test "the screen says what the workspace has chosen" do
    @workspace.update!(transcript_access_enabled: true, transcript_retention_days: 14)

    get settings_workspace_path, headers: {
      "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s
    }

    assert_response :success
    settings = JSON.parse(response.body).dig("props", "settings")
    assert settings["transcriptAccessEnabled"]
    assert_equal 14, settings["transcriptRetentionDays"]
  end

  # Zero or negative makes the cutoff now, so the next nightly run would purge every terminal incident's conversation.
  test "a retention that would purge everything is refused" do
    patch settings_workspace_path, params: { transcript_retention_days: 0 }

    assert_not_equal 0, @workspace.reload.transcript_retention_days
    assert_equal [ "must be greater than 0" ],
                 session[:inertia_errors].deep_stringify_keys["transcript_retention_days"]
  end

  # An integer column turns junk into 0 silently, which is the same purge.
  test "a retention that is not a number is refused" do
    patch settings_workspace_path, params: { transcript_retention_days: "abc" }

    assert_not_equal 0, @workspace.reload.transcript_retention_days
  end

  test "the archive delay is stored as the minutes behind the choice" do
    patch settings_workspace_path, params: { archive_channel_delay: "1440" }

    assert_redirected_to settings_workspace_path
    @workspace.reload
    assert @workspace.archive_channel_enabled
    assert_equal 1440, @workspace.archive_channel_delay_minutes
    assert_equal "1440", @workspace.archive_channel_delay
  end

  # Turning archiving off keeps the delay, so turning it back on lands on what the workspace had.
  test "never turns archiving off and keeps the delay for later" do
    @workspace.update!(archive_channel_enabled: true, archive_channel_delay_minutes: 360)

    patch settings_workspace_path, params: { archive_channel_delay: Workspace::ARCHIVE_DELAY_NEVER }

    @workspace.reload
    assert_not @workspace.archive_channel_enabled
    assert_equal 360, @workspace.archive_channel_delay_minutes
    assert_equal Workspace::ARCHIVE_DELAY_NEVER, @workspace.archive_channel_delay
  end

  # An integer column turns junk into 0, which would archive immediately.
  test "a delay the screen does not offer is refused" do
    patch settings_workspace_path, params: { archive_channel_delay: "45" }

    assert_equal 60, @workspace.reload.archive_channel_delay_minutes
    assert_equal [ "is not one of the offered delays" ],
                 session[:inertia_errors].deep_stringify_keys["archive_channel_delay"]

    patch settings_workspace_path, params: { archive_channel_delay: "soon" }

    assert_equal 60, @workspace.reload.archive_channel_delay_minutes
  end

  test "the screen says when channels are archived" do
    @workspace.update!(archive_channel_enabled: false)

    get settings_workspace_path, headers: {
      "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s
    }

    settings = JSON.parse(response.body).dig("props", "settings")
    assert_equal Workspace::ARCHIVE_DELAY_NEVER, settings["archiveChannelDelay"]
  end

  test "a member without workspace permission cannot turn it on" do
    sign_in(users(:bob), @workspace)
    WorkspaceMembership.any_instance.stubs(:implicitly_permits?).returns(false)

    patch settings_workspace_path, params: { transcript_access_enabled: true }

    assert_not @workspace.reload.transcript_access_enabled
  end

  test "an admin chooses the issue tracker, when items get issues, where they go and the webhook secret, and is told it saved" do
    linear = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", slug: "linear", settings: {})

    patch settings_workspace_path, params: { issue_tracker: "linear", issue_creation: Workspace::IssueSync::ISSUE_CREATION_FOLLOW_UPS,
                                             issue_tracker_target: { team: "ENG" }, issue_webhook_secret: "whsec" }

    assert_redirected_to settings_workspace_path
    assert_equal "Workspace settings were updated.", flash[:notice]
    @workspace.reload
    assert_equal [ linear.slug, Workspace::IssueSync::ISSUE_CREATION_FOLLOW_UPS, { "team" => "ENG" }, "whsec" ],
                 [ @workspace.issue_tracker, @workspace.issue_creation, @workspace.issue_tracker_target, @workspace.issue_webhook_secret ]

    get settings_workspace_path, headers: inertia_headers
    props = inertia_props
    assert_equal api_v1_issue_events_url(@workspace.issue_webhook_token), props["issueWebhookUrl"]
    assert props.dig("settings", "issueWebhookSecretSet")
    assert_not response.body.include?("whsec")
  end
end
