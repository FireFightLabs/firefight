require "test_helper"

class Chat::MemoryReviewTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @review = Chat::MemoryReview.open!(@workspace)
  end

  test "a night has one review" do
    assert @review
    assert_nil Chat::MemoryReview.open!(@workspace)
    assert Chat::MemoryReview.open!(@workspace, on: Date.tomorrow)
  end

  test "removals stop at tonight's limit" do
    @review.update!(removal_cap: 2)

    assert @review.take_removal!
    assert @review.take_removal!
    assert_not @review.take_removal!
    assert_equal 2, @review.reload.removals
  end

  test "a removal given back can be taken again, and never goes below none" do
    @review.update!(removal_cap: 1)
    @review.give_back_removal!
    assert_equal 0, @review.removals

    assert @review.take_removal!
    @review.give_back_removal!
    assert @review.take_removal!
  end

  test "each picked memory is settled once, and one not picked is refused" do
    picked = remember("web deploys from main")
    @review.picked!([ picked ])

    assert_equal Chat::Memory::VERDICT_UNSURE, @review.settle!(picked, verdict: Chat::Memory::VERDICT_UNSURE, evidence: "Nothing connected reads deploys.").outcome
    again = @review.settle!(picked, verdict: Chat::Memory::VERDICT_RIGHT, evidence: "The settings name main.")
    stranger = @review.settle!(remember("Backups run nightly"), verdict: Chat::Memory::VERDICT_RIGHT, evidence: "The job ran.")

    assert_nil again.outcome
    assert_match "settled already tonight", again.words
    assert_match "is not one of tonight's", stranger.words
    assert_equal Chat::Memory::STATE_UNCONFIRMED, picked.reload.state
  end

  test "a verdict that changes nothing, such as one decided on meanwhile, can be settled again" do
    picked = remember("Checkout runs in Frankfurt")
    @review.picked!([ picked ])
    picked.update!(state: Chat::Memory::STATE_REJECTED)

    assert_nil @review.settle!(picked.reload, verdict: Chat::Memory::VERDICT_RIGHT, evidence: "The settings say Frankfurt.").outcome
    assert_empty @review.reload.settled_ids
  end

  test "when the run ends, whatever it never settled is marked as tried tonight, once" do
    settled = remember("web deploys from main")
    missed = remember("Backups run nightly")
    @review.picked!([ settled, missed ])
    @review.settle!(settled, verdict: Chat::Memory::VERDICT_RIGHT, evidence: "The settings name main.")

    assert @review.finish!
    assert_not @review.finish!

    assert_equal [ nil, nil, Chat::MemoryReview::NOT_REACHED ], [ missed.reload.checked_at, missed.check_outcome, missed.events.sole.detail ]
    assert_equal missed, Chat::Memory.to_check(@workspace).first, "never checked, so it comes before what was"
    assert_equal "Checked 1 of 2 memories against production. 1 not reached, kept as not checked.", @review.reload.summary
  end

  private

  def remember(text) = Chat::Memory.create!(workspace: @workspace, text: text, state: Chat::Memory::STATE_UNCONFIRMED)
end
