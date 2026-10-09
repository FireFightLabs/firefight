require "test_helper"

class AiAccountLowBalanceJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
    Rails.configuration.x.ai_low_balance_usd = 10.0
  end

  test "a key below the threshold alerts once, however many checks find it low within the interval" do
    FirefightAi::Balance.stubs(:key).with("openrouter").returns(FirefightAi::Balance::Key.new(remaining: 7.25, usage: 92.75))

    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::LOW_BALANCE, 7.25, 92.75 ]) do
      2.times { AiAccountLowBalanceJob.perform_now }
    end
    assert_enqueued_jobs 1, only: AiAccountAlertJob

    travel AiAccount::ALERT_INTERVAL + 1.minute do
      AiAccountLowBalanceJob.perform_now
    end
    assert_enqueued_jobs 2, only: AiAccountAlertJob
  end

  test "a key at or above the threshold, one with no limit of its own, or one that cannot be read alerts nobody" do
    Rails.configuration.x.ai_low_balance_usd = 5.0
    FirefightAi::Balance.stubs(:key).with("openrouter")
                        .returns(FirefightAi::Balance::Key.new(remaining: 7.25, usage: 1.0))
                        .then.returns(FirefightAi::Balance::Key.new(remaining: nil, usage: 1.0))
                        .then.returns(nil)

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { 3.times { AiAccountLowBalanceJob.perform_now } }
  end

  test "with no webhook set nothing is sent, and that is logged" do
    Rails.configuration.x.install_notification_webhook_url = nil
    FirefightAi::Balance.stubs(:key).with("openrouter").returns(FirefightAi::Balance::Key.new(remaining: 1.0, usage: 99.0))
    Rails.logger.stubs(:info)
    Rails.logger.expects(:info).with { |line| line.include?("ai.account_alert_unsent") }

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { AiAccountLowBalanceJob.perform_now }
    assert_nil AiAccount.find_by(provider: "openrouter")&.alerted_at
  end
end
