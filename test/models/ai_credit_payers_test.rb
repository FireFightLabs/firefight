require "test_helper"

# What a person is told when nobody could pay, by who was meant to. It never names the provider, and says where an
# admin fixes what is theirs to fix.
class AiCreditPayersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a cloud workspace with no account and no credits is told it has none set up" do
    on_firefights_cloud!

    assert_equal "Halon cannot answer right now because this workspace has no AI account set up. " \
                 "An admin can fix this under Settings, Workspace, AI accounts.", AiCredit.cannot(@workspace)
  end

  test "credits that ran out say so, and where the hosted build sells more" do
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, true))

    assert_equal "Halon cannot write this postmortem right now because this workspace's Firefight credits are used up. " \
                 "An admin can buy more under Settings, Billing.", AiCredit.cannot(@workspace, "write this postmortem")
  end

  test "credits that ran out on a backend that does not say where to buy more point at the AI accounts" do
    credit = Class.new do
      def spendable? = false
      def used? = true
    end
    on_firefights_cloud!(credit: credit.new)

    assert_equal "Halon cannot answer right now because this workspace's Firefight credits are used up. " \
                 "An admin can fix this under Settings, Workspace, AI accounts.", AiCredit.cannot(@workspace)
  end

  test "the workspace's own account out of credit, or with its key refused, is the admin's to fix" do
    on_firefights_cloud!
    account = add_ai_account!(@workspace, provider: "openrouter", key: "sk-or-own", label: "OpenRouter")
    account.ran_out!(FirefightAi::OutOfCredit.new)

    said = AiCredit.cannot(@workspace)
    assert_equal "Halon cannot answer right now because this workspace's AI account is out of credit. " \
                 "An admin can fix this under Settings, Workspace, AI accounts.", said
    assert_no_match(/openrouter/i, said)

    account.update_columns(out_of_credit_since: nil, failing_since: Time.current)
    assert_equal "Halon cannot answer right now because this workspace's AI account refused its key. " \
                 "An admin can fix this under Settings, Workspace, AI accounts.", AiCredit.cannot(@workspace)
  end

  test "an install on its own keys says Halon could not reach its AI once the workspace's own accounts are spent" do
    add_ai_account!(@workspace).ran_out!(FirefightAi::OutOfCredit.new)

    assert_equal "Halon couldn't reach its AI just now.", AiCredit.cannot(@workspace)
  end
end
