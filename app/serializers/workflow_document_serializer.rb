# The version the canvas draws: its trigger, every step with what the canvas shows on it, every connection, and what
# publishing, restoring or discarding it would say. A version not saved yet is the empty one a new workflow starts with.
class WorkflowDocumentSerializer < BaseSerializer
  object_as :version

  type :string, optional: true
  def id
    version.id
  end

  type :number, optional: true
  def number
    version.number
  end

  type "#{Workflow::Version::STATUSES.map(&:inspect).join(' | ')}"
  def status
    version.status
  end

  type :number
  def revision
    version.revision
  end

  type :boolean
  def saved
    version.persisted?
  end

  # A draft is changed in place, and changing the live version opens a draft from it. An older one is only read.
  type :boolean
  def editable
    !version.persisted? || version.draft? || version.live?
  end

  type :string
  def author_name
    version.by_halon? ? "Halon" : (version.author&.actor_display_name || "Someone")
  end

  type :boolean
  def by_halon
    version.by_halon?
  end

  type :string, optional: true
  def reason
    version.reason
  end

  has_one :trigger, serializer: WorkflowTriggerSerializer do
    version.trigger
  end

  # Each step, given the facts, the workflow and what last changed each thing through the options.
  has_many :steps, serializer: WorkflowStepNodeSerializer do
    version.placed_steps
  end

  type "{ from: string; to: string; route: string | null; within: string | null; changedByHalon: boolean }[]"
  def edges
    version.placed_edges.map do |edge|
      target = Workflow::Edit::Operations.edge_target(edge)
      { from: edge["from"], to: edge["to"], route: edge["route"].presence, within: edge["within"], changedByHalon: last_changes[target]&.by_halon? || false }
    end
  end

  type "Record<string, unknown>"
  def outputs
    version.outputs
  end

  type :boolean
  def trigger_changed_by_halon
    last_changes[Workflow::Edit::TARGET_TRIGGER]&.by_halon? || false
  end

  # Each problem that stops it being published, as a sentence.
  type "string[]"
  def problems
    version.draft? ? version.problems : []
  end

  type :string, optional: true
  def publish_blocked_reason
    return "Change something first, so there is a draft to publish." unless version.persisted?

    version.publish_blocked_reason
  end

  type :string, optional: true
  def restore_blocked_reason
    version.persisted? ? version.restore_blocked_reason : "There is nothing to restore yet."
  end

  private

  def last_changes = options[:last_changes].to_h
end
