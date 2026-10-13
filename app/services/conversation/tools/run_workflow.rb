# Runs a published workflow by its name or another name it goes by, such as "release firefight production", once the
# person confirmed it on the card, which shows its steps and the inputs it runs with. It runs as the workflow's own
# identity, so what it may do is what an admin granted it, and the person needs only the right to run workflows.
class Conversation::Tools::RunWorkflow < RubyLLM::Tool
  NAME = "run_workflow".freeze
  WORKFLOW_ARG = "workflow".freeze
  INPUTS_ARG = "inputs".freeze

  description "Run a published workflow by its name or another name it goes by (list_workflows names them), such as a release the " \
              "person asks for by name. First tell the person what it will do and the inputs it uses, and ask for any input it has " \
              "no default for. The person confirms the run on a card before it starts. It runs as the workflow's own identity, and " \
              "its page shows each step as it goes."

  def self.tool_name = NAME

  def initialize(turn)
    super()
    @turn = turn
  end

  def name = NAME

  def parameters_schema
    schema = {
      "type" => "object",
      "properties" => {
        WORKFLOW_ARG => { "type" => "string", "description" => "The workflow's name, slug or another name it goes by" },
        INPUTS_ARG => { "type" => "object", "description" => "A value for each input by its key, such as {\"service\": \"web\"} (optional for one with a default)" }
      },
      "required" => [ WORKFLOW_ARG ]
    }
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  def requires_approval? = @turn.asker.present?

  def approval_resolver = Chat::Tools::Target.resolver(@turn) { |given| refusal_before(given).present? }

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    refused = refusal_before(given)
    return refused(tool_call, refused) if refused

    workflow = self.class.find(@turn.workspace, given[WORKFLOW_ARG])
    run = @turn.tool_call(action_key: Workflow::CREATE_KEY, params: { WORKFLOW_ARG => workflow.slug }) do
      WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_HALON, started_by: (@turn.asker if @turn.asker.is_a?(WorkspaceMembership)),
                                              inputs: given[INPUTS_ARG].to_h)
    end.value
    "Started #{workflow.name}. Its run: #{Workflow::Links.run(run)}. Tell the person it is running and where they can follow it."
  rescue Workflow::Run::Refused => error
    refused(tool_call, error.message)
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    refused(tool_call, "#{@turn.asker_name} is not allowed to run workflows.")
  end

  def self.find(workspace, named) = Workflow.named(workspace.workflows, named)

  # What the confirmation shows: each step it will take and the inputs it runs with, read from the workflow.
  def self.plan_rows(workspace, arguments)
    given = arguments.to_h.stringify_keys
    workflow = find(workspace, given[WORKFLOW_ARG])
    return [] unless workflow&.live_version

    version = workflow.live_version
    kinds = version.step_kinds
    resolved = Workflow::Trigger.resolve_inputs(version.trigger, given[INPUTS_ARG])
    steps = Workflow::Version.all_steps(version.steps).map do |step|
      kind = kinds[step["id"]]
      [ kind&.label || step["kind"].to_s.humanize, [ step["name"], kind&.describe(step["config"].to_h, workspace).presence ].compact.join(": ") ]
    end
    inputs = resolved.values.map { |key, value| [ "Input #{key}", value.to_s ] }
    inputs + steps
  end

  private

  def refusal_before(given)
    return "Workflows are run for a person, and nobody is asking in this chat." unless @turn.asker

    workflow = self.class.find(@turn.workspace, given[WORKFLOW_ARG])
    return "No workflow is called #{given[WORKFLOW_ARG]}. list_workflows names them." unless workflow

    blocked = workflow.start_blocked_reason
    return blocked if blocked

    missing = Workflow::Trigger.resolve_inputs(workflow.live_version.trigger, given[INPUTS_ARG]).missing
    "Ask the person first: #{missing.map { |input| input['question'] }.join(' ')} Then call it again with #{INPUTS_ARG}." if missing.any?
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    text
  end
end
