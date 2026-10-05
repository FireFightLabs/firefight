require "test_helper"

class Workspace::IssueSyncTest < ActiveSupport::TestCase
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @linear = connect_tracker!(@workspace, provider: "linear")
  end

  test "never is the default, and opening issues needs a tracker" do
    assert_equal Workspace::IssueSync::ISSUE_CREATION_NEVER, @workspace.issue_creation
    assert_not @workspace.update(issue_creation: Workspace::IssueSync::ISSUE_CREATION_ALL)
    assert @workspace.errors[:issue_creation].any?
  end

  test "only a connection to a tracker that keeps items in step can be chosen" do
    other = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "notion", name: "Notion", slug: "notion", settings: {})

    assert_not @workspace.update(issue_tracker: other.slug)
    assert @workspace.update(issue_tracker: @linear.slug)
    assert_includes @workspace.issue_tracker_choices.map(&:value), @linear.slug
    assert_not_includes @workspace.issue_tracker_choices.map(&:value), other.slug
  end

  test "choosing a tracker gives the workspace its webhook address, and choosing another forgets the secret and the target" do
    sync_with!(@workspace, @linear)
    token = @workspace.issue_webhook_token
    assert token.present?
    assert @workspace.issue_webhook_secret_set?

    jira = connect_tracker!(@workspace, provider: "jira")
    @workspace.update!(issue_tracker: jira.slug)

    assert_equal token, @workspace.issue_webhook_token
    assert_not @workspace.issue_webhook_secret_set?
    assert_equal({}, @workspace.issue_tracker_target)
    assert_match "until its webhook's signing secret is saved", @workspace.issue_webhook_blocked_reason
  end

  test "the blocked reasons name a missing target, a switched off tool and a removed or disabled connection" do
    sync_with!(@workspace, @linear, target: {})
    assert_equal "Say which team new issues go to.", @workspace.issue_creation_blocked_reason

    @workspace.update!(issue_tracker_target: { "team" => "ENG" })
    assert_nil @workspace.issue_creation_blocked_reason

    @linear.tools.find_by!(name: "save_issue").update!(enabled: false)
    assert_match "save_issue tool is switched off", @workspace.issue_creation_blocked_reason

    @linear.update!(disabled_at: Time.current)
    assert_match "is switched off, so no issues are opened", @workspace.issue_creation_blocked_reason

    @linear.update!(deleted_at: Time.current)
    assert_match "was removed", @workspace.issue_creation_blocked_reason
  end

  test "the secret is read back only as whether one is saved, and an empty one keeps what is saved" do
    sync_with!(@workspace, @linear, secret: "whsec")

    @workspace.update_settings!(issue_webhook_secret: "", issue_creation: Workspace::IssueSync::ISSUE_CREATION_ALL)

    assert_equal "whsec", @workspace.reload.issue_webhook_secret
    assert_not @workspace.settings.key?(:issue_webhook_secret)
    assert @workspace.settings[:issue_webhook_secret_set]
  end
end
