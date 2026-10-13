# Every kind of step a workspace's workflow can hold, one class each. A kind says what it is called, whether it reads or
# changes (decided by what it calls, never by whoever wrote the step), what it hands later steps, what makes its config
# wrong, what its workflow's own identity needs granted to run it, and how it runs. The engine runs its own control kinds
# (branch, delay and the rest), so their classes only describe them. Adding a kind is its class and a line in kinds.
module DefinedWorkflow::Steps
  # Read when first asked rather than when this file loads, since each kind's class loads this namespace first.
  def self.kinds
    @kinds ||= [
      DefinedWorkflow::Steps::CallTool, DefinedWorkflow::Steps::AskHalon, DefinedWorkflow::Steps::RunSkill,
      DefinedWorkflow::Steps::Watch, DefinedWorkflow::Steps::PostToChannel, DefinedWorkflow::Steps::RaiseNotice,
      DefinedWorkflow::Steps::Investigate, DefinedWorkflow::Steps::Classify, DefinedWorkflow::Steps::OpenIncident,
      DefinedWorkflow::Steps::UpdateIncident, DefinedWorkflow::Steps::PostIncidentUpdate, DefinedWorkflow::Steps::PageOnCall,
      DefinedWorkflow::Steps::CreateFollowUp, DefinedWorkflow::Steps::MessagePerson, DefinedWorkflow::Steps::StatusPageUpdate,
      DefinedWorkflow::Steps::RunCommand, DefinedWorkflow::Steps::RunScript, DefinedWorkflow::Steps::CheckFromOutside, DefinedWorkflow::Steps::Browser,
      DefinedWorkflow::Steps::HttpRequest, DefinedWorkflow::Steps::SendWebhook,
      DefinedWorkflow::Steps::Branch, DefinedWorkflow::Steps::Delay
    ].freeze
  end

  def self.registry = @registry ||= kinds.index_by(&:kind).freeze

  # The kinds DefinedWorkflow runs itself, rather than the engine.
  def self.action_kinds = kinds.reject(&:engine?).map(&:kind)

  def self.for(kind) = registry[kind.to_s]
end
