# Reads a workflow as the canvas shows it, with the kinds of step Halon may add, before it proposes a change. A read of
# the workflow through the gateway, ledgered like any other.
class Chat::Tools::GetWorkflow < RubyLLM::Tool
  include Chat::Tools::WorkflowAccess

  NAME = "get_workflow".freeze

  def name = NAME

  def description
    "Read a workflow as a person sees it on its canvas: its trigger, its steps with their ids, names and settings, how " \
      "they connect, the suggestions of yours still waiting on a person, and every kind of step you may add with the " \
      "settings it takes. Read it before proposing a change, and again after one, since people change it too."
  end

  def parameters_schema = { "type" => "object", "properties" => { "workflow" => WORKFLOW_PARAMETER } }

  def call(tool_call: nil, **arguments)
    reference = arguments.stringify_keys["workflow"]
    workflow = chosen_workflow(reference)
    return refused(tool_call, missing_workflow(reference)) unless workflow

    read = @agent_run.tool_call(action_key: Ability::Action::WORKFLOWS_READ, params: { workflow: workflow.slug }, tool_name: name, label: "Read #{workflow.name}") do
      JSON.pretty_generate(workflow.for_halon(facts: facts))
    end
    Chat::Tools.hand_over(@agent_run, name, read)
  rescue AbilityGateway::Denied => denied
    refused(tool_call, @agent_run.refusal(denied.action_key))
  rescue AbilityGateway::PendingApproval
    Chat::Tools.waiting_for_approval(Ability::Action::WORKFLOWS_READ)
  end

  private

  # The tools a Call a tool step may call, listed once that kind can run, since building the list reads every connection.
  def facts
    return Workflow::StepKinds::Facts.new(workspace: @agent_run.workspace) unless Workflow::StepKinds.runnable?(Workflow::StepKinds::KIND_CALL_TOOL)

    Workflow::StepKinds::Facts.new(workspace: @agent_run.workspace, tools: Chat::Tools::Choices.tools(@agent_run.workspace))
  end
end
