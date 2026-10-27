require "test_helper"

class Chat::Memory::CheckingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @review = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.current, removal_cap: 3)
  end

  test "tonight's picks are what changed since Halon last checked it, then what it never checked, then what it checked longest ago" do
    checked_long_ago = remember("Backups run nightly", checked_at: 20.days.ago, updated_at: 30.days.ago)
    checked_lately = remember("Checkout uses Redis", checked_at: 2.days.ago, updated_at: 30.days.ago)
    changed = remember("web deploys from main", checked_at: 5.days.ago, updated_at: 1.day.ago)
    never = remember("The primary is db-1", updated_at: 3.days.ago)
    remember("Old wording", state: Chat::Memory::STATE_REJECTED)
    remember("Nobody confirmed", state: Chat::Memory::STATE_EXPIRED)
    remember("Same as another", state: Chat::Memory::STATE_MERGED)

    assert_equal [ changed, never, checked_long_ago, checked_lately ], Chat::Memory.to_check(@workspace).to_a
    assert_equal [ changed, never ], Chat::Memory.to_check(@workspace, limit: 2).to_a
  end

  test "what Halon rejected is picked again once 90 days have passed since it last checked it, and what a person rejected never is" do
    halon = remember("Checkout runs in Frankfurt", state: Chat::Memory::STATE_REJECTED, decided_by_halon: true, rejected_at: 100.days.ago,
                                                   checked_at: 100.days.ago, updated_at: 100.days.ago)
    remember("Checkout runs in Paris", state: Chat::Memory::STATE_REJECTED, decided_by_halon: true, rejected_at: 10.days.ago, checked_at: 10.days.ago)
    remember("Checkout runs in Rome", state: Chat::Memory::STATE_REJECTED, rejected_by: @alice, rejected_at: 100.days.ago, checked_at: 100.days.ago)

    assert_equal [ halon ], Chat::Memory.to_check(@workspace).to_a
  end

  test "checked again and right, what Halon rejected is in use again as confirmed by Halon, may be learned again, and what replaced it is rejected" do
    old = remember("The primary is db-1")
    old.found_wrong_by_halon!(evidence: "The cluster lists db-2 as primary.", correction: "The primary is db-2", review: @review)
    replacement = old.reload.replaced_by
    later = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.tomorrow, removal_cap: 3)

    settled = old.verified_by_halon!(evidence: "The cluster lists db-1 as primary again.", review: later)

    assert_equal [ Chat::Memory::STATE_CONFIRMED, true, nil, nil ], old.reload.values_at(:state, :decided_by_halon, :replaced_by_id, :rejected_at)
    assert_match "Restored.", settled.words
    assert_equal Chat::MemoryEvent::KIND_RESTORED, old.events.last.kind
    assert_equal Chat::Memory::STATE_REJECTED, replacement.reload.state
    learned = Chat::Memory.learn!(@workspace, text: "The primary is db-1", subject: nil, source: nil)
    assert_equal [ Chat::Memory::LEARNED_KNOWN, old ], [ learned.outcome, learned.memory ]
  end

  test "checked again and still wrong, what Halon rejected stays rejected and waits another 90 days, using no removal" do
    old = remember("Checkout retries twice")
    old.found_wrong_by_halon!(evidence: "The client sets three retries.", correction: nil, review: @review)
    later = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.tomorrow, removal_cap: 3)

    settled = old.found_wrong_by_halon!(evidence: "The client still sets three retries.", correction: nil, review: later)

    assert_equal "Still wrong, so it stays rejected.", settled.words
    assert_equal [ Chat::Memory::STATE_REJECTED, Chat::Memory::VERDICT_WRONG ], old.reload.values_at(:state, :check_outcome)
    assert_equal [ Chat::MemoryEvent::KIND_REJECTED, Chat::MemoryEvent::KIND_STILL_WRONG ], old.events.map(&:kind)
    assert_equal 0, later.reload.removals
  end

  test "each line of history Halon's check writes links the run that checked it" do
    run = @workspace.investigations.create!(subject: @review, trigger_source: Investigation::TRIGGER_MEMORY_REVIEW, max_turns: 4, max_spend_cents: 400)
    memory = remember("web deploys from main")

    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)

    assert_equal run, memory.reload.last_verified.investigation
  end

  test "a night may reject or merge 15 percent of the memories in use, and never fewer than three" do
    assert_equal 3, Chat::Memory.removal_cap(@workspace)

    40.times { |index| remember("Fact number #{index}") }
    assert_equal 6, Chat::Memory.removal_cap(@workspace)
  end

  test "shown right, what nobody stood behind counts as confirmed by Halon with the evidence and the date kept" do
    memory = remember("web deploys from main")

    settled = memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)

    memory.reload
    assert_equal Chat::Memory::VERDICT_RIGHT, settled.outcome
    assert_equal [ Chat::Memory::STATE_CONFIRMED, true, nil, Chat::Memory::STANDING_HALON ], [ memory.state, memory.decided_by_halon, memory.confirmed_by, memory.standing ]
    assert_equal memory.checked_at, memory.updated_at, "a check is never read as a change since the check"
    assert_equal [ Chat::MemoryEvent::KIND_VERIFIED, Chat::MemoryEvent::ACTOR_HALON, "The deploy settings of web name main." ],
                 memory.last_verified.values_at(:kind, :actor, :detail)
    assert_equal "Halon", memory.decider
    assert_match "checked by Halon against production on #{Date.current.iso8601}", memory.line
  end

  test "shown right, a person's confirmation stays theirs, with Halon's check kept beside it" do
    memory = remember("web deploys from main", state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @alice, confirmed_at: 3.days.ago)

    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)

    memory.reload
    assert_equal [ Chat::Memory::STATE_CONFIRMED, @alice, false, Chat::Memory::STANDING_PERSON ], [ memory.state, memory.confirmed_by, memory.decided_by_halon, memory.standing ]
    assert_equal Chat::Memory::VERDICT_RIGHT, memory.check_outcome
    assert memory.last_verified
  end

  test "shown right, the memory it contradicted is rejected with the evidence, and a person's is disputed for them instead" do
    older = remember("web deploys from main")
    newer = remember("web deploys from release")
    older.contradicted!(newer, reason: "A chat showed \"web deploys from release\".")

    newer.verified_by_halon!(evidence: "The deploy settings of web name release.", review: @review)

    assert_equal [ Chat::Memory::STATE_REJECTED, newer.id, true ], older.reload.values_at(:state, :replaced_by_id, :decided_by_halon)
    assert_match "Halon checked \"web deploys from release\" against production and it holds.", older.state_reason
    assert_equal 1, @review.reload.removals

    personal = remember("Checkout runs in Frankfurt", state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @alice, confirmed_at: 2.days.ago)
    dublin = remember("Checkout runs in Dublin")
    personal.contradicted!(dublin, reason: "A chat showed \"Checkout runs in Dublin\".")
    dublin.verified_by_halon!(evidence: "The service's settings say Dublin.", review: @review)

    assert_equal [ Chat::Memory::STATE_DISPUTED, @alice ], personal.reload.values_at(:state, :confirmed_by)
    assert personal.awaiting_decision?, "Halon found evidence against a person's memory, so it waits on them"
  end

  test "shown wrong with what is right instead, Halon corrects it, and the correction is confirmed by Halon with the same evidence" do
    memory = remember("The primary is db-1")

    settled = memory.found_wrong_by_halon!(evidence: "The cluster lists db-2 as primary.", correction: "The primary is db-2", review: @review)

    replacement = memory.reload.replaced_by
    assert_equal "Corrected. Halon now remembers \"The primary is db-2\" instead.", settled.words
    assert_equal [ Chat::Memory::STATE_REJECTED, true, nil ], memory.values_at(:state, :decided_by_halon, :rejected_by_id)
    assert_equal [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::STANDING_HALON ], [ replacement.state, replacement.standing ]
    assert_equal "The cluster lists db-2 as primary.", replacement.last_verified.detail
    assert_equal [ Chat::MemoryEvent::KIND_CORRECTED ], memory.events.map(&:kind)
  end

  test "shown wrong with nothing to put in its place, Halon rejects it, and a correction Halon may not keep is refused with why" do
    memory = remember("Checkout retries twice")

    assert_raises(Chat::Memory::Refused) do
      memory.found_wrong_by_halon!(evidence: "The client sets three retries.", correction: "Checkout currently runs 3 replicas", review: @review)
    end
    assert_equal [ Chat::Memory::STATE_UNCONFIRMED, 0 ], [ memory.reload.state, @review.reload.removals ]

    memory.found_wrong_by_halon!(evidence: "The client sets three retries.", correction: nil, review: @review)

    assert_equal [ Chat::Memory::STATE_REJECTED, "The client sets three retries.", nil ], memory.reload.values_at(:state, :state_reason, :replaced_by_id)
    assert_equal "Halon", memory.decider
  end

  test "a person's memory is never rejected by Halon, only disputed, and never again with evidence they already saw" do
    memory = remember("web deploys from main", state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @alice, confirmed_at: 5.days.ago)

    first = memory.found_wrong_by_halon!(evidence: "The deploy settings of web name release.", correction: "web deploys from release", review: @review)

    assert_equal [ memory.id ], first.challenged, "the person who confirmed it is told"
    assert_equal [ Chat::Memory::STATE_DISPUTED, @alice, nil ], memory.reload.values_at(:state, :confirmed_by, :replaced_by_id)
    assert memory.awaiting_decision?
    assert_equal 0, @review.reload.removals, "a dispute removes nothing"

    travel 1.minute
    memory.confirm!(by: @alice)
    travel 1.day
    settled = memory.found_wrong_by_halon!(evidence: "The deploy settings of web name release.", correction: nil, review: @review)

    assert_equal Chat::Memory::OUTCOME_HELD, settled.outcome
    assert_empty settled.challenged, "nothing new, so nobody is told again"
    assert_equal [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::OUTCOME_HELD ], memory.reload.values_at(:state, :check_outcome)

    memory.found_wrong_by_halon!(evidence: "The deploy log shows the last three deploys came from the hotfix branch.", correction: nil, review: @review)
    assert_equal Chat::Memory::STATE_DISPUTED, memory.reload.state, "new evidence is raised again"
  end

  test "a person confirming a memory while Halon's check runs is never rejected by that check, and the removal goes back" do
    memory = remember("Checkout retries twice")
    stale = Chat::Memory.find(memory.id)
    memory.confirm!(by: @alice)
    stale.define_singleton_method(:person_stands_behind?) { false }

    settled = stale.found_wrong_by_halon!(evidence: "The client sets three retries.", correction: nil, review: @review)

    assert_nil settled.outcome
    assert_match "changed while you checked it", settled.words
    assert_equal [ Chat::Memory::STATE_CONFIRMED, @alice ], memory.reload.values_at(:state, :confirmed_by)
    assert_equal 0, @review.reload.removals
  end

  test "a person confirming the other side of a contradiction while Halon's check runs is not rejected, and the removal goes back" do
    older = remember("web deploys from main")
    newer = remember("web deploys from release")
    older.contradicted!(newer, reason: "A chat showed \"web deploys from release\".")
    stale_older = Chat::Memory.find(older.id)
    older.confirm!(by: @alice)
    stale_older.define_singleton_method(:person_stands_behind?) { false }

    assert_nil stale_older.send(:settle_against!, newer, "The deploy settings of web name release.", @review, [])
    assert_equal [ Chat::Memory::STATE_CONFIRMED, @alice ], older.reload.values_at(:state, :confirmed_by)
    assert_equal 0, @review.reload.removals
  end

  test "Halon checking again what a person confirmed never moves the date they confirmed it" do
    confirmed_at = 3.days.ago.change(usec: 0)
    memory = remember("web deploys from main", state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @alice, confirmed_at: confirmed_at)

    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)

    assert_equal confirmed_at, memory.reload.confirmed_at
    assert_equal Chat::Memory::VERDICT_RIGHT, memory.check_outcome
  end

  test "two people confirming at once what only Halon confirmed land once" do
    memory = remember("web deploys from main")
    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)
    first = Chat::Memory.find(memory.id)
    second = Chat::Memory.find(memory.id)
    bob = workspace_memberships(:bob_workspace_one)

    assert first.confirm!(by: @alice)
    assert_not second.confirm!(by: bob)
    assert_equal @alice, memory.reload.confirmed_by
  end

  test "past tonight's limit a wrong memory is left as it was, marked as held, and checked again another night" do
    @review.update!(removal_cap: 1)
    first = remember("Checkout retries twice")
    second = remember("Checkout runs in Frankfurt")

    first.found_wrong_by_halon!(evidence: "The client sets three retries.", correction: nil, review: @review)
    settled = second.found_wrong_by_halon!(evidence: "The settings say Dublin.", correction: nil, review: @review)

    assert_equal Chat::Memory::OUTCOME_HELD, settled.outcome
    assert_equal [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::OUTCOME_HELD ], second.reload.values_at(:state, :check_outcome)
    assert_equal Chat::MemoryEvent::KIND_HELD, second.events.sole.kind
  end

  test "neither right nor wrong, it is kept as it was with when it was last tried, which is never a change and never moves its expiry" do
    memory = remember("Checkout runs in Frankfurt", updated_at: 10.days.ago)

    memory.unsettled_by_halon!(note: "Nothing Halon reads says where Checkout runs.")

    memory.reload
    assert_equal [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::VERDICT_UNSURE, Chat::Memory::STANDING_UNCHECKED ], [ memory.state, memory.check_outcome, memory.standing ]
    assert_in_delta 10.days.ago, memory.updated_at, 5.seconds
    assert_not memory.awaiting_decision?, "an unchecked memory asks nobody"
  end

  test "only a contradiction Halon tried and could not settle waits on a person" do
    older = remember("Checkout runs in Frankfurt")
    older.contradicted!(remember("Checkout runs in Dublin"), reason: "A chat showed \"Checkout runs in Dublin\".")
    lone = remember("Backups run nightly")
    lone.dispute!("The backup job did not run last night.")

    assert_not older.reload.awaiting_decision?
    older.unsettled_by_halon!(note: "Nothing Halon reads says where Checkout runs.")
    lone.unsettled_by_halon!(note: "The backup job's history is not connected.")

    assert older.reload.awaiting_decision?
    assert_not lone.reload.awaiting_decision?
  end

  test "a person may confirm what only Halon confirmed, which makes it theirs, and a person's word clears Halon's" do
    memory = remember("web deploys from main")
    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: @review)
    assert_nil memory.reload.confirm_blocked_reason

    assert memory.confirm!(by: @alice)

    assert_equal [ @alice, false, Chat::Memory::STANDING_PERSON ], [ memory.reload.confirmed_by, memory.decided_by_halon, memory.standing ]
    assert_equal "It is confirmed already.", memory.confirm_blocked_reason
    assert_equal [ Chat::MemoryEvent::KIND_VERIFIED, Chat::MemoryEvent::KIND_CONFIRMED ], memory.events.map(&:kind)
  end

  private

  def remember(text, state: Chat::Memory::STATE_UNCONFIRMED, **columns)
    Chat::Memory.create!(workspace: @workspace, text: text, state: state, **columns)
  end
end
