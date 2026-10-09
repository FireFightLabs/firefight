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

  test "an account below the threshold alerts once, however many checks find it low within the interval" do
    FirefightAi::Balance.stubs(:account).with("openrouter").returns(FirefightAi::Balance::Account.new(remaining: 7.25, usage: 92.75))

    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::LOW_BALANCE, 7.25, 92.75 ]) do
      2.times { AiAccountLowBalanceJob.perform_now }
    end
    assert_enqueued_jobs 1, only: AiAccountAlertJob

    travel AiAccount::ALERT_INTERVAL + 1.minute do
      AiAccountLowBalanceJob.perform_now
    end
    assert_enqueued_jobs 2, only: AiAccountAlertJob
  end

  test "an account at or above the threshold, or one that cannot be read, alerts nobody" do
    Rails.configuration.x.ai_low_balance_usd = 5.0
    FirefightAi::Balance.stubs(:account).with("openrouter")
                        .returns(FirefightAi::Balance::Account.new(remaining: 7.25, usage: 1.0))
                        .then.returns(nil)

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { 2.times { AiAccountLowBalanceJob.perform_now } }
  end

  test "without the management key nothing is read, and the run says so once in the log" do
    FirefightAi.configuration.stubs(:provider_settings).returns(openrouter_api_key: "sk-or-key")
    FirefightAi.configuration.stubs(:openrouter_management_key).returns(nil)
    Net::HTTP.expects(:start).never
    logged = []
    Rails.logger.stubs(:info).with { |line| logged << line }

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { AiAccountLowBalanceJob.perform_now }
    unchecked = logged.select { |line| line.to_s.include?("ai.balance_unchecked") }.map { |line| JSON.parse(line) }
    assert_equal [ { "event" => "ai.balance_unchecked", "provider" => "openrouter", "missing" => "OPENROUTER_MANAGEMENT_KEY" } ], unchecked
  end

  test "with no webhook set nothing is sent, and that is logged" do
    Rails.configuration.x.install_notification_webhook_url = nil
    FirefightAi::Balance.stubs(:account).with("openrouter").returns(FirefightAi::Balance::Account.new(remaining: 1.0, usage: 99.0))
    Rails.logger.stubs(:info)
    Rails.logger.expects(:info).with { |line| line.include?("ai.account_alert_unsent") }

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { AiAccountLowBalanceJob.perform_now }
    assert_nil AiAccount.find_by(provider: "openrouter")&.alerted_at
  end
end
