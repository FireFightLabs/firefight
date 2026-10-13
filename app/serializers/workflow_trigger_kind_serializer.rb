# A kind of trigger the canvas offers, from the registry (Workflow::TriggerKinds).
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
    kind.fields.map(&:to_h)
  end

  type "#{Workflow::TriggerKinds::EDITORS.map(&:inspect).join(' | ')}"
  def editor
    kind.editor
  end

  type "Record<string, unknown>"
  def defaults
    kind.defaults
  end
end
