# Tonight's look at what one workspace remembers. It merges memories that say the same thing about the same subject,
# picks up to Chat::Memory::Checking::NIGHTLY_LIMIT memories in code, and starts the run that checks them against
# production as the investigator, within its grants, its map reach and the workspace's spend limits. Merges and
# rejections share one limit a night (Chat::MemoryReview#take_removal!).
class MemoryReviewService
  def initialize(workspace)
    @workspace = workspace
  end

  # The night's review, or nil when Halon cannot run here or this night already has one.
  def start!(on: Date.current)
    return nil if Investigation.start_refusal(@workspace)

    review = Chat::MemoryReview.open!(@workspace, on: on)
    return nil unless review

    picks = Chat::Memory.to_check(@workspace).to_a
    merge!(review, picks)
    # A pick merged away lives on in the one it was merged into.
    still = Chat::Memory.where(id: picks.map(&:id), state: Chat::Memory::CHECKED_STATES).pluck(:id).to_set
    review.picked!(picks.select { |memory| still.include?(memory.id) })
    return review.tap(&:finish!) if review.memory_ids.empty?

    started = InvestigationService.new(@workspace).start(review, trigger_source: Investigation::TRIGGER_MEMORY_REVIEW)
    review.finish! unless started
    review
  end

  private

  # Same wording is merged without asking anyone. A pick the quick model reads as saying the same as another memory about
  # the same subject is merged too. A judge that cannot answer, such as when the account is out of credit, merges by
  # wording only.
  def merge!(review, picks)
    judge = FirefightAi::MemoryJudge.new(@workspace, inferable: review)
    picked = picks.map(&:id).to_set
    Chat::Memory.mergeable_by_subject(@workspace).each_value do |peers|
      next if peers.size < 2
      break if @refused

      pairs = peers.select { |memory| picked.include?(memory.id) }.flat_map { |memory| judged_same(judge, memory, peers) }
      Chat::Memory.duplicate_sets(peers, same_pairs: pairs).each { |set| merge_set!(review, set) }
    end
  end

  def judged_same(judge, memory, peers)
    others = peers.reject { |peer| peer.id == memory.id }.first(Chat::Memory::JUDGED_LIMIT)
    known = others.map { |peer| FirefightAi::MemoryJudge::Known.new(id: peer.id, text: peer.text) }
    judge.verdicts(fact: memory.text, known: known)
         .select { |verdict| verdict.verdict == FirefightAi::Schemas::MemoryVerdicts::SAME }.map { |verdict| [ memory.id, verdict.id ] }
  rescue FirefightAi::Error => error
    Rails.logger.info({ event: "memory_review.judge_failed", workspace_id: @workspace.id, error: error.class.name }.to_json)
    []
  end

  def merge_set!(review, set)
    keeper = Chat::Memory.strongest(set)
    set.each do |memory|
      next if memory.id == keeper.id
      break unless review.take_removal!

      merged = Chat::Memory.changed_by_halon(@workspace, Ability::Action::ACTION_UPDATE, params: { "memory" => memory.id, "merged_into" => keeper.id }) do
        memory.merge_into!(keeper)
      end
      if merged
        review.class.where(id: review.id).update_all("merged = merged + 1")
        next
      end

      # Nothing was merged, so the removal goes back. A refusal means the investigator may no longer change memory, so
      # nothing else is merged tonight.
      review.give_back_removal!
      @refused = merged.nil?
      break if @refused
    end
    review.reload
  end
end
