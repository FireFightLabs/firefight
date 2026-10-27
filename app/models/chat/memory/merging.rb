# Memories that say the same thing about the same subject are merged into one each night. The one kept is the one with
# the strongest trust, and each merged one stays in its history as merged into it (replaced_by), never deleted.
module Chat::Memory::Merging
  extend ActiveSupport::Concern

  # Only what Halon uses is merged. A disputed, rejected or expired memory waits or was set aside for a reason.
  MERGEABLE_STATES = [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_OUTDATED ].freeze

  class_methods do
    # The workspace's memories that may be merged, grouped by what they are about.
    def mergeable_by_subject(workspace)
      where(workspace: workspace, state: MERGEABLE_STATES).order(:created_at).to_a.group_by { |memory| [ memory.subject_type, memory.subject_id ] }
    end

    # Each set of memories about one subject that say the same thing: the same wording (Words.signature), or a pair the
    # judge read as the same, joined through any memory they share. same_pairs holds pairs of ids.
    def duplicate_sets(peers, same_pairs: [])
      parent = peers.to_h { |memory| [ memory.id, memory.id ] }
      root = ->(id) { parent[id] == id ? id : (parent[id] = root.(parent[id])) }
      join = ->(one, other) { parent[root.(one)] = root.(other) if parent.key?(one) && parent.key?(other) }
      peers.group_by { |memory| Chat::Memory::Words.signature(memory.text) }.each_value { |same| same.each_cons(2) { |one, other| join.(one.id, other.id) } }
      same_pairs.each { |one, other| join.(one, other) }
      peers.group_by { |memory| root.(memory.id) }.values.select { |set| set.size > 1 }
    end

    # The memory a set is merged into: a person's confirmation first, then a postmortem's, then Halon's, then one in use
    # over one flagged outdated, then the most used, then the oldest.
    def strongest(set)
      set.min_by do |memory|
        trust = if memory.confirmed_by_id then 0
        elsif memory.confirmed? && memory.decided_by_postmortem_id then 1
        elsif memory.confirmed? && memory.decided_by_halon then 2
        elsif memory.state == Chat::Memory::STATE_UNCONFIRMED then 3
        else 4
        end
        [ trust, -memory.use_count, memory.created_at ]
      end
    end
  end

  # Merged into keeper, which takes over its uses and anything that pointed at it. Guarded, so a memory someone decided
  # on meanwhile, or one a person stands behind, is left alone. Returns whether it was merged.
  def merge_into!(keeper)
    transaction do
      moved = decide!(Chat::Memory::STATE_MERGED, from: MERGEABLE_STATES, decided_by_halon: true, halon_only: true, replaced_by_id: keeper.id,
                                                  state_reason: "It says the same as \"#{keeper.text}\".")
      next false unless moved

      self.class.where(contradicted_by_id: id).update_all(contradicted_by_id: keeper.id)
      self.class.where(replaced_by_id: id).where.not(id: keeper.id).update_all(replaced_by_id: keeper.id)
      self.class.where(id: keeper.id).update_all([ "use_count = use_count + ?, last_used_at = GREATEST(last_used_at, ?)", use_count, last_used_at ])
      record!(Chat::MemoryEvent::KIND_MERGED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: "It said the same as \"#{keeper.text}\".")
      keeper.record!(Chat::MemoryEvent::KIND_ABSORBED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: "\"#{text}\" said the same and was merged into this one.")
      true
    end
  end
end
