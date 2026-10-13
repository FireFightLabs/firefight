class RunbookWorkflowChoiceSerializer < BaseSerializer
  object_as :workflow

  type :string
  def id = workflow.id

  attributes(name: { type: :string })

  type "#{Workflow::STATES.map(&:inspect).join(' | ')}"
  def state = workflow.state
end
