# A draft changes one edit at a time, each saved with one update guarded on the revision it was made on, so two people
# editing at once never overwrite each other. An edit made on an older revision still lands on top of the newer one,
# unless something it touches changed since, in which case it is refused naming who changed it.
module Workflow::Version::Drafting
  extend ActiveSupport::Concern

  # Each try reads the draft again, so only a burst of edits to other steps can keep it going this long.
  MAX_TRIES = 5

  def apply_edit!(attributes, base_revision: nil)
    attributes = attributes.dup
    operation = attributes.delete(:operation)
    payload = attributes.delete(:payload)
    targets = Workflow::Edit::Operations.targets(operation, payload)

    apply_operation!(operation, payload, base_revision: base_revision || revision, targets: targets) do |applied_revision, seen_revision|
      edits.create!(attributes.merge(workflow_id: workflow_id, operation: operation, payload: payload, targets: targets,
                                     status: Workflow::Edit::STATUS_APPLIED, base_revision: seen_revision, applied_revision: applied_revision))
    end
  end

  # Yields the revision the edit produced and the one it was made on, inside the transaction that saved it.
  def apply_operation!(operation, payload, base_revision:, targets: Workflow::Edit::Operations.targets(operation, payload))
    MAX_TRIES.times do
      reload
      raise Workflow::Edit::Refused, "Only a draft can be changed, so open a draft first." unless draft?

      refuse_if_changed_since!(base_revision, targets) if revision > base_revision
      changed = Workflow::Edit::Operations.apply(snapshot, operation, payload)
      problem = self.class.content_problem(changed)
      raise Workflow::Edit::Refused, problem if problem
      current = revision

      result = transaction(requires_new: true) do
        moved = self.class.where(id: id, status: Workflow::Version::STATUS_DRAFT, revision: current)
                          .update_all(**changed.slice(*Workflow::Version::CONTENT).symbolize_keys, revision: current + 1, updated_at: Time.current)
        next :again unless moved == 1

        yield current + 1, base_revision
      end
      next if result == :again

      reload
      return result
    end
    raise Workflow::Edit::Refused, "The draft is changing too fast to save this, so try again."
  end

  private

  def refuse_if_changed_since!(base_revision, targets)
    clash = edits.landed.where("applied_revision > ?", base_revision).where("targets && ARRAY[?]::varchar[]", targets)
                 .order(applied_revision: :desc).first
    return unless clash

    who = clash.by_halon? ? "Halon" : (clash.author&.actor_display_name || "Someone")
    raise Workflow::Edit::Refused, "#{who} changed this since you looked, so look again before changing it."
  end
end
