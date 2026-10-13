# A kind of trigger the canvas offers, from the registry (Workflow::TriggerKinds): its words and icon, how its settings
# are drawn, what its conditions may read with the workspace's values for each, and what its run's trigger data holds.
class WorkflowTriggerKindSerializer < BaseSerializer
  object_as :kind

  type :string
  def key
    kind.key
  end

  type :string
  def label
    kind.label
  end

  type :string
  def description
    kind.description
  end

  type "#{Workflow::TriggerKinds::ICONS.map(&:inspect).join(' | ')}"
  def icon
    kind.icon
  end

  type "{ key: string; kind: #{ToolField::KINDS.map(&:inspect).join(' | ')}; options: string[]; required: boolean; description: string | null }[]"
  def fields
    kind.fields_for(facts).map(&:to_h)
  end

  type "#{Workflow::TriggerKinds::EDITORS.map(&:inspect).join(' | ')}"
  def editor
    kind.editor
  end

  type "Record<string, unknown>"
  def defaults
    kind.defaults
  end

  type :boolean
  def event
    kind.event?
  end

  type "{ key: string; label: string; options: { value: string; label: string }[] }[]"
  def conditions
    kind.conditions_for(facts).map { |field| { key: field.key, label: field.label, options: field.options.map(&:to_h) } }
  end

  type "{ path: string; label: string }[]"
  def outputs
    kind.outputs.map(&:to_h)
  end

  private

  def facts = options[:facts] || Workflow::StepKinds::Facts.new
end
