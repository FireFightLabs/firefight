require "test_helper"

class AiAccountAlertJobTest < ActiveSupport::TestCase
  setup do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
    AiAccount.create!(provider: "openrouter", out_of_credit_since: Time.utc(2026, 10, 6, 14, 29))
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
  end

  test "the people running Firefight are told which account ran out and when, where new installs are announced" do
    TeamWebhook.expects(:post!).with { |payload| payload[:text].start_with?("The openrouter AI account ran out of credit at 14:29 UTC on 6 October.") }

    AiAccountAlertJob.perform_now("openrouter")
  end

  test "nothing is sent for an account that has credit again, or with nowhere to send it" do
    TeamWebhook.expects(:post!).never

    AiAccountAlertJob.perform_now("anthropic")
    Rails.configuration.x.install_notification_webhook_url = nil
    AiAccountAlertJob.perform_now("openrouter")
  end
end
