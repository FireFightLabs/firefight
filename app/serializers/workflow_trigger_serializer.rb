# A version's trigger as the canvas draws its first node: its kind with the registry's words for it, the inputs a
# person is asked when they run it by hand, and its other settings as stored.
class WorkflowTriggerSerializer < BaseSerializer
  object_as :trigger

  type :string
  def kind
    trigger.to_h[Workflow::Trigger::KEY_KIND].to_s
  end

  type :string
  def label
    Workflow::TriggerKinds.find(kind)&.label || kind.tr("_", " ").upcase_first
  end

  type "#{Workflow::TriggerKinds::ICONS.map(&:inspect).join(' | ')}"
  def icon
    Workflow::TriggerKinds.find(kind)&.icon || Workflow::TriggerKinds::ICON_WORKFLOW
  end

  type "{ key: string; question: string; default: string | null }[]"
  def inputs
    Workflow::Trigger.inputs(trigger).map { |input| { key: input["key"].to_s, question: input["question"].to_s, default: input["default"].presence } }
  end

  type "Record<string, unknown>"
  def config
    trigger.to_h.except(Workflow::Trigger::KEY_KIND, Workflow::Trigger::KEY_INPUTS)
  end
end
