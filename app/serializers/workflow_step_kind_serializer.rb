# A kind of step the palette offers, from the registry (Workflow::StepKinds): its group, name, line and icon, how its
# settings are drawn, the fields they take and what a new one starts with.
class WorkflowStepKindSerializer < BaseSerializer
  object_as :kind

  type :string
  def key
    kind.key
  end

  type "#{Workflow::StepKinds::GROUPS.map(&:inspect).join(' | ')}"
  def group
    kind.group
  end

  type :string
  def label
    kind.label
  end

  type :string
  def description
    kind.description
  end

  type "#{Workflow::StepKinds::ICONS.map(&:inspect).join(' | ')}"
  def icon
    kind.icon
  end

  type "#{Workflow::StepKinds::EDITORS.map(&:inspect).join(' | ')}"
  def editor
    kind.editor
  end

  type "{ key: string; kind: #{ToolField::KINDS.map(&:inspect).join(' | ')}; options: string[]; required: boolean; description: string | null }[]"
  def fields
    kind.fields_for(facts).map(&:to_h)
  end

  type "Record<string, unknown>"
  def defaults
    kind.defaults
  end

  type "string[]"
  def outputs
    kind.outputs.call({ "kind" => kind.key, "config" => kind.defaults }, facts)
  end

  private

  def facts = options[:facts] || Workflow::StepKinds::Facts.new
end
