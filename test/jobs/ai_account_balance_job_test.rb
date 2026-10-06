require "test_helper"

class AiAccountBalanceJobTest < ActiveSupport::TestCase
  setup do
    @account = AiAccount.create!(provider: "openrouter", out_of_credit_since: 2.hours.ago)
  end

  test "an account whose balance shows credit again stops reading as out" do
    FirefightAi::Balance.expects(:remaining).with("openrouter").returns(12.5)

    AiAccountBalanceJob.perform_now

    assert_nil @account.reload.out_of_credit_since
    assert @account.balance_checked_at
  end

  test "a balance too small to last, or one that cannot be read, leaves it out" do
    FirefightAi::Balance.stubs(:remaining).returns(0.07).then.returns(nil)

    2.times { AiAccountBalanceJob.perform_now }

    assert @account.reload.out_of_credit_since
    assert @account.balance_checked_at
  end
end
