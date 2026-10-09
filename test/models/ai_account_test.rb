require "test_helper"

class AiAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "running out alerts once, however many calls are refused, and an answered call brings it back" do
    assert_enqueued_with(job: AiAccountAlertJob, args: [ "openrouter" ]) { assert AiRefusal.house_ran_out!("openrouter") }
    assert_no_enqueued_jobs(only: AiAccountAlertJob) { assert_not AiRefusal.house_ran_out!("openrouter") }

    since = AiAccount.find_by!(provider: "openrouter").out_of_credit_since
    assert since

    assert AiAccount.answered!("openrouter")
    assert_nil AiAccount.find_by!(provider: "openrouter").out_of_credit_since
    assert_not AiAccount.answered!("openrouter"), "an account with credit changes nothing"
    assert_enqueued_with(job: AiAccountAlertJob) { AiRefusal.house_ran_out!("openrouter") }
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
