require "test_helper"

class AiAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
  end

  test "running out alerts once, however many calls are refused, and an answered call brings it back" do
    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::OUT_OF_CREDIT ]) { assert AiRefusal.house_ran_out!("openrouter") }
    assert_no_enqueued_jobs(only: AiAccountAlertJob) { assert_not AiRefusal.house_ran_out!("openrouter") }

    since = AiAccount.find_by!(provider: "openrouter").out_of_credit_since
    assert since

    assert AiAccount.answered!("openrouter")
    assert_nil AiAccount.find_by!(provider: "openrouter").out_of_credit_since
    assert_not AiAccount.answered!("openrouter"), "an account with credit changes nothing"
  end

  test "a key refused again after the alert interval is reported again, and a low balance inside it stays quiet" do
    AiRefusal.house_ran_out!("openrouter")
    assert_no_enqueued_jobs(only: AiAccountAlertJob) { AiAccountAlert.low_balance!("openrouter", FirefightAi::Balance::Account.new(remaining: 1.0, usage: 2.0)) }

    travel AiAccount::ALERT_INTERVAL + 1.minute do
      assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::OUT_OF_CREDIT ]) { AiRefusal.house_ran_out!("openrouter") }
    end
  end

  test "running out is told even right after a low balance alert" do
    AiAccountAlert.low_balance!("openrouter", FirefightAi::Balance::Account.new(remaining: 1.0, usage: 2.0))

    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::OUT_OF_CREDIT ]) { assert AiRefusal.house_ran_out!("openrouter") }
  end

  test "running out again after a refill is told at once, within the interval of the last time" do
    AiRefusal.house_ran_out!("openrouter")
    AiAccount.answered!("openrouter")

    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter", AiAccountAlert::OUT_OF_CREDIT ]) { assert AiRefusal.house_ran_out!("openrouter") }
  end

  test "of alerts racing each other only one may send" do
    assert AiAccount.low_balance_alert_due!("openrouter")
    assert_not AiAccount.low_balance_alert_due!("openrouter")
    assert AiAccount.low_balance_alert_due!("anthropic"), "each key has its own interval"
    assert AiAccount.out_of_credit_alert_due!("openrouter", fresh: false), "running out has its own interval"
    assert_not AiAccount.out_of_credit_alert_due!("openrouter", fresh: false)
  end

  test "a refusal with no webhook set records it, sends nothing, and says so in the log" do
    Rails.configuration.x.install_notification_webhook_url = nil
    Rails.logger.stubs(:info)
    Rails.logger.expects(:info).with { |line| line.include?("ai.account_alert_unsent") }

    assert_no_enqueued_jobs(only: AiAccountAlertJob) { assert AiRefusal.house_ran_out!("openrouter") }
    assert AiAccount.find_by!(provider: "openrouter").out_of_credit_since
  end

  test "the model only records that it ran out, and enqueues nothing" do
    assert_no_enqueued_jobs { assert AiAccount.ran_out!("openrouter") }
  end

  test "an answered call in the ledger brings its provider's account back" do
    AiAccount.ran_out!("openrouter")

    Inference.track(workspace: workspaces(:slack_workspace_one), feature: "conversation", provider: "openrouter", model: "gpt-4o") { llm_reply(content: "ok") }

    assert_empty AiAccount.out_of_credit
  end
end
