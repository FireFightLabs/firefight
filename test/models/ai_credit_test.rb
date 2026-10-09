require "test_helper"

class AiCreditTest < ActiveSupport::TestCase
  # Stands in for the cloud build's backend, which never says whose account it is.
  HostedBackend = Struct.new(:unused) do
    def check(_workspace, _feature) = Entitlements.allow
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  teardown do
    Entitlements.reset_backend!
    Rails.configuration.x.install_notification_webhook_url = nil
  end

  test "an install on its own keys tells people whoever runs it needs to add credit" do
    assert_equal Entitlements::AI_ACCOUNT_OPERATOR, Entitlements.ai_account(@workspace)
    assert_equal "Halon cannot answer right now because the AI account behind this Firefight is out of credit. " \
                 "Whoever runs Firefight needs to add credit.", AiCredit.cannot(@workspace)
  end

  test "an install on its own keys whose team gets alerts is told the same as Firefight's cloud" do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"

    assert_equal "Halon couldn't reach its AI just now. The team has been told.", AiCredit.cannot(@workspace)
  end

  test "a workspace on its own AI account keeps its own notice when an alert reaches the team" do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
    on_firefights_cloud!
    add_ai_account!(@workspace).ran_out!(FirefightAi::OutOfCredit.new)

    assert_equal "Halon cannot answer right now because this workspace's AI account is out of credit. " \
                 "An admin can fix this under Settings, Workspace, AI accounts.", AiCredit.cannot(@workspace)
  end

  test "on Firefight's cloud people hear only that Halon could not reach its AI, and only when an alert reaches the team" do
    Entitlements.backend = HostedBackend.new
    assert_equal Entitlements::AI_ACCOUNT_FIREFIGHT, Entitlements.ai_account(@workspace)

    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
    assert_equal "Halon couldn't reach its AI just now. The team has been told.", AiCredit.cannot(@workspace)
    assert_equal "Halon couldn't reach its AI just now. The team has been told.", AiCredit.cannot(@workspace, "write this postmortem")

    Rails.configuration.x.install_notification_webhook_url = nil
    assert_equal "Halon cannot write this postmortem right now because the AI account behind this workspace is out of credit. " \
                 "Firefight's team can see this.", AiCredit.cannot(@workspace, "write this postmortem")
  end
end
