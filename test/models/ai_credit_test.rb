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

  test "on Firefight's cloud the team is said to be told only when an alert reaches it" do
    Entitlements.backend = HostedBackend.new
    assert_equal Entitlements::AI_ACCOUNT_FIREFIGHT, Entitlements.ai_account(@workspace)

    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
    assert_equal "Halon cannot answer right now because the AI account behind this workspace is out of credit. " \
                 "Firefight's team has been told.", AiCredit.cannot(@workspace)

    Rails.configuration.x.install_notification_webhook_url = nil
    assert_equal "Halon cannot write this postmortem right now because the AI account behind this workspace is out of credit. " \
                 "Firefight's team can see this.", AiCredit.cannot(@workspace, "write this postmortem")
  end
end
