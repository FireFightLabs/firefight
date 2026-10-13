# One change of Halon's that landed, as Changes by Halon lists it: what it did, why, who accepted it, the steps it
# touched so the canvas can mark them, and why it cannot be undone when it cannot.
class WorkflowHalonChangeSerializer < BaseSerializer
  object_as :change

  type :string
  def key
    change.key.to_s
  end

  # The change set to undo, or nil when Halon made the edit on its own.
  type :string, optional: true
  def change_set_id
    change.edits.first.change_set_id
  end

  type :string
  def edit_id
    change.edits.first.id
  end

  type "string[]"
  def sentences
    change.edits.map(&:sentence)
  end

  type :string, optional: true
  def reason
    change.reason
  end

  type :string, optional: true
  def accepted_by_name
    change.edits.first.decided_by&.actor_display_name
  end

  type "string[]"
  def step_ids
    change.edits.flat_map(&:targets).uniq
  end

  type :number
  def version_number
    change.version.number
  end

  type :string, optional: true
  def undo_blocked_reason
    options[:workflow].undo_blocked_reason(change.edits)
  end

  type :string
  def created_at
    change.created_at.iso8601
  end
end
