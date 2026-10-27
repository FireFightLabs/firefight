require "test_helper"

class MemoryReviewServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Investigation.stubs(:start_refusal).returns(nil)
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([])
  end

  test "a night merges what says the same thing, picks the rest in code and starts one run that checks them as the investigator" do
    kept = remember("web deploys from main", use_count: 4)
    duplicate = remember("Web deploys from main.")
    other = remember("Backups run nightly")

    review = nil
    assert_enqueued_with(job: InvestigationJob) { review = MemoryReviewService.new(@workspace).start! }

    assert_equal [ Chat::Memory::STATE_MERGED, kept.id ], duplicate.reload.values_at(:state, :replaced_by_id)
    assert_equal [ kept.id, other.id ].sort, review.memory_ids.sort
    assert_equal [ 1, 1 ], review.values_at(:merged, :removals)
    run = review.investigations.sole
    assert_equal [ Investigation::TRIGGER_MEMORY_REVIEW, nil, SystemAgent.investigator ], [ run.trigger_source, run.triggered_by, run.acting_principal ]
    assert_equal [ Investigation::STATUS_PENDING, "Nightly memory check" ], [ run.status, run.label ]
    entry = @workspace.ability_invocations.find_by!(action_key: "memory.update", principal: SystemAgent.investigator)
    assert_equal [ AbilityGateway::SOURCE_INVESTIGATION, duplicate.id ], [ entry.source, entry.params["memory"] ]
    assert_nil MemoryReviewService.new(@workspace).start!, "one review a night"
  end

  test "a pick the quick model reads as saying the same as another memory about the same subject is merged too, within tonight's limit" do
    first = remember("main is the branch web ships from", created_at: 2.days.ago)
    same = remember("web deploys from main")
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).returns([ FirefightAi::MemoryJudge::Verdict.new(id: same.id, verdict: FirefightAi::Schemas::MemoryVerdicts::SAME) ])

    review = MemoryReviewService.new(@workspace).start!

    assert_equal [ Chat::Memory::STATE_MERGED, Chat::Memory::STATE_UNCONFIRMED ], [ same.reload.state, first.reload.state ]
    assert_equal 1, review.merged
  end

  test "merges stop at tonight's limit, and a judge that cannot answer merges by wording only" do
    FirefightAi::MemoryJudge.any_instance.stubs(:verdicts).raises(FirefightAi::TerminalError.new("out of credit", reason: "OutOfCredit"))
    5.times { remember("web deploys from main") }

    review = MemoryReviewService.new(@workspace).start!

    assert_equal 3, review.merged
    assert_equal 3, Chat::Memory.where(workspace: @workspace, state: Chat::Memory::STATE_MERGED).count
  end

  test "once an admin revokes the investigator's memory grant, nothing is merged in any set, no removal is spent, and the refusal is in Activity once" do
    @workspace.ability_grants.where(principal: SystemAgent.investigator, action: Ability::Action.where(key: "memory.update")).destroy_all
    duplicate = remember("Web deploys from main.")
    remember("web deploys from main")
    remember("Backups run nightly.", subject: catalog_entries(:auth_service))
    remember("backups run nightly", subject: catalog_entries(:auth_service))

    review = MemoryReviewService.new(@workspace).start!

    assert_not_equal Chat::Memory::STATE_MERGED, duplicate.reload.state
    assert_equal [ 0, 0 ], review.values_at(:merged, :removals)
    assert_equal 1, @workspace.ability_invocations.where(action_key: "memory.update", principal: SystemAgent.investigator, decision: Ability::Invocation::DECISION_DENY).count
  end

  test "a merge that does not happen, such as one a person decided on meanwhile, gives its removal back" do
    remember("web deploys from main")
    remember("Web deploys from main.")
    Chat::Memory.any_instance.stubs(:merge_into!).returns(false)

    review = MemoryReviewService.new(@workspace).start!

    assert_equal [ 0, 0 ], review.values_at(:merged, :removals)
  end

  test "a workspace Halon cannot run in gets no review, and one with nothing to check starts no run" do
    Investigation.stubs(:start_refusal).returns("AI features are not available.")
    remember("web deploys from main")
    assert_nil MemoryReviewService.new(@workspace).start!

    Investigation.stubs(:start_refusal).returns(nil)
    Chat::Memory.where(workspace: @workspace).delete_all
    review = nil
    assert_no_enqueued_jobs(only: InvestigationJob) { review = MemoryReviewService.new(@workspace).start! }
    assert review.finished_at
  end

  test "a workspace that turned the nightly check off gets no review" do
    remember("web deploys from main")
    @workspace.update!(memory_review_enabled: false)

    assert_nil MemoryReviewService.new(@workspace).start!
    assert_not Chat::MemoryReview.exists?(workspace: @workspace)
  end

  test "what Halon rejected 90 days ago is checked again tonight" do
    rejected = remember("Checkout runs in Frankfurt", state: Chat::Memory::STATE_REJECTED, decided_by_halon: true, rejected_at: 100.days.ago,
                                                      checked_at: 100.days.ago)

    review = MemoryReviewService.new(@workspace).start!

    assert_includes review.memory_ids, rejected.id
  end

  test "the nightly job reviews every workspace, and one failing never stops the next" do
    MemoryReviewService.any_instance.stubs(:start!).raises(StandardError, "boom").then.returns(nil)

    assert_nothing_raised { MemoryReviewJob.perform_now }
  end

  private

  def remember(text, state: Chat::Memory::STATE_UNCONFIRMED, **columns) = Chat::Memory.create!(workspace: @workspace, text: text, state: state, **columns)
end
