require "test_helper"

class AiAccountAlertJobTest < ActiveSupport::TestCase
  setup do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
    AiAccount.create!(provider: "openrouter", out_of_credit_since: Time.utc(2026, 10, 6, 14, 29))
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
    Rails.configuration.x.ai_alert_slack_user_id = nil
  end

  test "the people running Firefight are told which account ran out and when, where new installs are announced" do
    TeamWebhook.expects(:post!).with { |payload| payload[:text].start_with?("The openrouter AI account ran out of credit at 14:29 UTC on 6 October.") }

    AiAccountAlertJob.perform_now("openrouter", AiAccountAlert::OUT_OF_CREDIT)
  end

  test "a key running low says what it has left, what it spent and where alerts start, in plain text" do
    TeamWebhook.expects(:post!).with(text: "The openrouter AI key is running low. It has $7.25 left to spend, and has spent $92.75 in all. " \
                                           "Alerts start below $10.00. Add credit or raise the key's limit before Halon stops answering.")

    AiAccountAlertJob.perform_now("openrouter", AiAccountAlert::LOW_BALANCE, 7.25, 92.75)
  end

  test "the configured Slack user is tagged" do
    Rails.configuration.x.ai_alert_slack_user_id = "U012AB3CD"
    TeamWebhook.expects(:post!).with { |payload| payload[:text].start_with?("<@U012AB3CD> The openrouter AI account ran out of credit") }

    AiAccountAlertJob.perform_now("openrouter", AiAccountAlert::OUT_OF_CREDIT)
  end

  test "nothing is sent for an account that has credit again, or with nowhere to send it" do
    TeamWebhook.expects(:post!).never

    AiAccountAlertJob.perform_now("anthropic", AiAccountAlert::OUT_OF_CREDIT)
    Rails.configuration.x.install_notification_webhook_url = nil
    AiAccountAlertJob.perform_now("openrouter", AiAccountAlert::OUT_OF_CREDIT)
  end
end
