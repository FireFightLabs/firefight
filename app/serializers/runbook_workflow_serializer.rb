# Without options[:member] Run it is blocked only by how the workflow stands.
class RunbookWorkflowSerializer < BaseSerializer
  object_as :workflow

  type :string
  def id = workflow.id

  attributes(name: { type: :string })

  type "#{Workflow::STATES.map(&:inspect).join(' | ')}"
  def state = workflow.state

  type "{ key: string; question: string; default?: string }[]"
  def inputs
    Workflow::Trigger.inputs(workflow.live_version&.trigger).map { |input| { key: input["key"], question: input["question"], default: input["default"].presence }.compact }
  end

  type :string, optional: true
  def run_blocked_reason
    member = options[:member]
    member ? workflow.run_now_blocked_reason(member) : workflow.start_blocked_reason
  end
end
