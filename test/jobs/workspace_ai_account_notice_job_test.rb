require "test_helper"

class WorkspaceAiAccountNoticeJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "each admin is told by direct message which account stopped and that Halon moved on, never a member" do
    account = add_ai_account!(@workspace, label: "Team Anthropic")
    told = []
    adapter = mock("adapter")
    adapter.stubs(:post_notice).with { |user_id:, notice:| told << [ user_id, notice ] }.returns(success: true)
    WorkspaceAdapter.stubs(:for).returns(adapter)

    WorkspaceAiAccountNoticeJob.perform_now(account.id, WorkspaceAiAccount::NOTICE_OUT_OF_CREDIT)

    assert_equal [ "U12345678" ], told.map(&:first)
    notice = told.first.last
    assert_equal "Halon's AI account \"Team Anthropic\" ran out of credit", notice.title
    assert_equal "Open AI accounts", notice.link_label
    text = notice.fallback
    assert_match "Halon's AI account \"Team Anthropic\" ran out of credit. Halon is using the next one in the list.", text
    assert_match "Settings, Workspace, AI accounts", text
    assert_no_match(/anthropic\b(?!")/i, text.delete_prefix("Halon's AI account \"Team Anthropic\""))
    assert_no_match(/—|;/, text)
  end

  test "the notice is drawn in Slack as a warning title, what it means, and a button to the AI accounts page" do
    notice = PlatformAdapter::Notice.new(title: "Halon's AI account \"Team\" ran out of credit", body: "Halon is using the next one in the list.",
                                         link_label: "Open AI accounts", link_url: "https://app.example.com/settings/workspace", fallback: "x")

    blocks = Slack::Messages::Notice.build(notice)

    assert_equal %w[section divider section actions], blocks.pluck(:type)
    assert_equal "#{Slack::Emoji::WARNING}  *Halon's AI account \"Team\" ran out of credit*", blocks.first.dig(:text, :text)
    assert_equal "https://app.example.com/settings/workspace", blocks.last[:elements].sole[:url]
    assert_equal %w[section divider section], Slack::Messages::Notice.build(notice.with(link_url: nil)).pluck(:type)
  end

  test "an admin told with nothing left to fall back on hears that Halon cannot answer" do
    on_firefights_cloud!
    account = add_ai_account!(@workspace)
    account.key_refused!(FirefightAi::TerminalError.new("401", reason: "UnauthorizedError"))

    assert_match "had its key refused. Halon has no other account to use, so it cannot answer until this is fixed.",
                 WorkspaceAiAccountService.new(@workspace).notice_text(account, WorkspaceAiAccount::NOTICE_KEY_REFUSED)
  end
end
