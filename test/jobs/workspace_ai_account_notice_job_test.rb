require "test_helper"

class WorkspaceAiAccountNoticeJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "each admin is told by direct message which account stopped and that Halon moved on, never a member" do
    account = add_ai_account!(@workspace, label: "Team Anthropic")
    told = []
    adapter = mock("adapter")
    adapter.stubs(:post_direct_message).with { |user_id:, text:| told << [ user_id, text ] }.returns(success: true)
    WorkspaceAdapter.stubs(:for).returns(adapter)

    WorkspaceAiAccountNoticeJob.perform_now(account.id, WorkspaceAiAccount::NOTICE_OUT_OF_CREDIT)

    assert_equal [ "U12345678" ], told.map(&:first)
    text = told.first.last
    assert_match "Halon's AI account \"Team Anthropic\" ran out of credit. Halon is using the next one in the list.", text
    assert_match "Settings, Workspace, AI accounts", text
    assert_no_match(/anthropic\b(?!")/i, text.delete_prefix("Halon's AI account \"Team Anthropic\""))
    assert_no_match(/—|;/, text)
  end

  test "an admin told with nothing left to fall back on hears that Halon cannot answer" do
    on_firefights_cloud!
    account = add_ai_account!(@workspace)
    account.key_refused!(FirefightAi::TerminalError.new("401", reason: "UnauthorizedError"))

    assert_match "had its key refused. Halon has no other account to use, so it cannot answer until this is fixed.",
                 WorkspaceAiAccountService.new(@workspace).notice_text(account, WorkspaceAiAccount::NOTICE_KEY_REFUSED)
  end
end
