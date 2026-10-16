require "test_helper"

class AiCredit::PurchaseTest < ActiveSupport::TestCase
  include AiAccountTestHelper

  test "the starter credit is said in whole dollars, or with cents when it has them" do
    assert_equal "Includes $10 to get started. Buy more any time.", AiCredit::Purchase.starter_note(10_000_000)
    assert_equal "Includes $12.50 to get started. Buy more any time.", AiCredit::Purchase.starter_note(12_500_000)
  end

  test "the AI a plan includes is said as a monthly amount" do
    assert_equal "Your plan includes $25 of AI every month. Buy more any time.", AiCredit::Purchase.included_note(25_000_000)
  end

  test "the AI a plan includes is offered in place of a starter credit, with roughly what it buys" do
    workspace = workspaces(:slack_workspace_one)
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(true, false, 10_000_000, "$25.00", 25_000_000))

    purchase = AiCredit::Purchase.for(workspace, return_to: "/app/setup")

    assert_equal "Your plan includes $25 of AI every month. Buy more any time.", purchase[:note]
    assert_equal "As a rough guide, $25 is about 230 questions to Halon.", purchase[:estimate]
    assert_not purchase.key?(:includedMicros)
    assert_not purchase.key?(:starterMicros)
  end

  test "what the starter buys is an estimate from the average answer with the markup on top, rounded" do
    assert_equal "As a rough guide, $10 is about 90 questions to Halon.", AiCredit::Purchase.estimate(10_000_000, 20)
    assert_equal "As a rough guide, $25 is about 230 questions to Halon.", AiCredit::Purchase.estimate(25_000_000, 20)
    assert_equal "As a rough guide, $1 is about 9 questions to Halon.", AiCredit::Purchase.estimate(1_000_000, 20)
    assert_equal "As a rough guide, $0.10 is about 1 question to Halon.", AiCredit::Purchase.estimate(100_000, 20)
  end

  test "nothing is offered where credits are not sold, or by a hosted build that sells none from setup" do
    workspace = workspaces(:slack_workspace_one)
    assert_nil AiCredit::Purchase.for(workspace, return_to: "/app/setup")

    credit = Object.new
    on_firefights_cloud!(credit: credit)
    assert_nil AiCredit::Purchase.for(workspace, return_to: "/app/setup")
  end
end
