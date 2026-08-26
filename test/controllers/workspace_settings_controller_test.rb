require "test_helper"

# The screen that decides whether the conversation is readable at all. A grant
# says who may ask, and this says whether there is anything to ask for.
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

  # A blank retention is a choice, not an omission, so it stores as keep-forever
  # rather than being refused or falling back to the default.
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

  # Zero or negative makes the cutoff now, so the next nightly run would purge
  # every terminal incident's conversation in the workspace.
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

  test "a member without workspace permission cannot turn it on" do
    sign_in(users(:bob), @workspace)
    WorkspaceMembership.any_instance.stubs(:implicitly_permits?).returns(false)

    patch settings_workspace_path, params: { transcript_access_enabled: true }

    assert_not @workspace.reload.transcript_access_enabled
  end
end
