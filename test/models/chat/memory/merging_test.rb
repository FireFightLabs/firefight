require "test_helper"

class Chat::Memory::MergingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @checkout = catalog_entries(:auth_service)
  end

  test "memories about one subject in the same words, or that the judge read as the same, are one set, joined through any they share" do
    one = remember("web deploys from main")
    reworded = remember("Web deploys from MAIN.")
    same_meaning = remember("main is the branch web ships from")
    other = remember("web runs two instances")
    elsewhere = remember("web deploys from main", subject: @checkout)

    by_subject = Chat::Memory.mergeable_by_subject(@workspace)
    sets = Chat::Memory.duplicate_sets(by_subject[[ nil, nil ]], same_pairs: [ [ same_meaning.id, reworded.id ] ])

    assert_equal [ [ one, reworded, same_meaning ].map(&:id).sort ], sets.map { |set| set.map(&:id).sort }
    assert_not_includes sets.flatten, other
    assert_equal [ [ elsewhere ] ], [ by_subject[[ CatalogEntry.name, @checkout.id ]] ]
  end

  test "the one kept has the strongest trust: a person, then a postmortem, then Halon, then in use, then the most used, then the oldest" do
    halon = remember("web deploys from main", state: Chat::Memory::STATE_CONFIRMED, decided_by_halon: true, confirmed_at: Time.current)
    person = remember("web deploys from main", state: Chat::Memory::STATE_CONFIRMED, confirmed_by: @alice, confirmed_at: Time.current)
    used = remember("web deploys from main", use_count: 9)
    older = remember("web deploys from main", created_at: 3.days.ago)

    assert_equal person, Chat::Memory.strongest([ halon, used, older, person ])
    assert_equal halon, Chat::Memory.strongest([ halon, used, older ])
    assert_equal used, Chat::Memory.strongest([ used, older ])
    assert_equal older, Chat::Memory.strongest([ older, remember("web deploys from main") ])
  end

  test "a merged memory lives on in the one kept, which takes over its uses and whatever pointed at it, both with the merge in their history" do
    keeper = remember("web deploys from main", use_count: 2, last_used_at: 3.days.ago)
    merged = remember("Web deploys from main.", use_count: 3, last_used_at: 1.day.ago)
    disputed = remember("web deploys from release", state: Chat::Memory::STATE_DISPUTED, contradicted_by: merged)

    assert merged.merge_into!(keeper)

    assert_equal [ Chat::Memory::STATE_MERGED, keeper.id, true ], merged.reload.values_at(:state, :replaced_by_id, :decided_by_halon)
    assert_equal 5, keeper.reload.use_count
    assert_in_delta 1.day.ago, keeper.last_used_at, 5.seconds
    assert_equal keeper.id, disputed.reload.contradicted_by_id
    assert_equal [ Chat::MemoryEvent::KIND_MERGED ], merged.events.map(&:kind)
    assert_equal [ Chat::MemoryEvent::KIND_ABSORBED ], keeper.events.map(&:kind)
    assert_not merged.in_use?
    assert_equal "It was merged into another memory that says the same thing.", merged.reject_blocked_reason
    assert_not merged.merge_into!(keeper), "a memory already merged is left alone"
  end

  test "a memory a person confirmed while the night's merge was getting ready is never merged" do
    keeper = remember("web deploys from main")
    duplicate = remember("Web deploys from main.")
    stale = Chat::Memory.find(duplicate.id)
    duplicate.confirm!(by: @alice)

    assert_not stale.merge_into!(keeper)
    assert_equal [ Chat::Memory::STATE_CONFIRMED, @alice ], duplicate.reload.values_at(:state, :confirmed_by)
  end

  test "learning the wording of a merged memory again finds the one kept" do
    keeper = remember("web deploys from main")
    remember("Web deploys from main.").merge_into!(keeper)

    learned = Chat::Memory.learn!(@workspace, text: "web deploys from main", subject: nil, source: nil)

    assert_equal [ Chat::Memory::LEARNED_KNOWN, keeper ], [ learned.outcome, learned.memory ]
  end

  test "a run told a starting memory was merged since hears which one it lives on in" do
    keeper = remember("web deploys from main")
    merged = remember("Web deploys from main.")
    merged.merge_into!(keeper)

    change = Chat::Memory.change_since_start(merged.id, merged.reload)

    assert_equal "merged:#{keeper.id}", change.key
    assert_match "said the same as memory #{keeper.id} (web deploys from main)", change.note
  end

  private

  def remember(text, subject: nil, state: Chat::Memory::STATE_UNCONFIRMED, **columns)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: state, **columns)
  end
end
