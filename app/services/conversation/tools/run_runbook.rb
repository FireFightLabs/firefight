# Runs a saved runbook, such as Release Firefight, once the person confirmed what it will do, by starting the workflow
# it links as that workflow's own identity.
class Conversation::Tools::RunRunbook < RubyLLM::Tool
  NAME = "run_runbook".freeze
  RUNBOOK_ARG = "runbook".freeze
  INPUTS_ARG = "inputs".freeze

  description "Run a saved runbook by its name, slug or another name it goes by (search_runbooks says which are runnable), " \
              "which starts the workflow it links, such as Release Firefight. First tell the person what it will do and which " \
              "inputs it uses, and ask for any input it has no default for. The person confirms the run before it starts. It " \
              "runs as the workflow's own identity with only what an admin granted it, and its page shows each step as it goes. " \
              "When a request matches a saved runbook, such as a release or a rollback, run it rather than doing its steps one " \
              "by one. When the person has you do the same multi-step task again, offer to save it as a workflow."

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
        RUNBOOK_ARG => { "type" => "string", "description" => "The runbook's name, slug or another name it goes by" },
        INPUTS_ARG => { "type" => "object", "description" => "A value for each of the runbook's inputs by its key, such as {\"bump\": \"patch\"} (optional for one with a default)" }
      },
      "required" => [ RUNBOOK_ARG ]
    }
    requires_approval? ? Chat::Tools.with_intent(schema) : schema
  end

  # A run changes things in several places at once, so the person confirms it first, unless they allowed runbooks for
  # the rest of this chat and nothing read from outside has reached it since. A request that would be refused anyway is let through at once, so the refusal reaches Halon
  # and nobody is asked about a run that cannot start.
  def requires_approval? = @turn.asker.present? && !Chat::Tools::Provenance.allowed?(@turn, NAME)

  def approval_resolver = Chat::Tools::Target.resolver(@turn) { |given| refusal_before_running(given).present? }

  def call(tool_call: nil, **arguments)
    given = arguments.transform_keys(&:to_s)
    refused = refusal_before_running(given)
    return refused(tool_call, refused) if refused

    start_workflow(find(given), given, tool_call)
  end

  # What the confirmation shows under the question: the steps of the workflow it starts, so the person confirms the run
  # itself rather than Halon's words about it.
  def self.plan_rows(workspace, arguments)
    given = arguments.to_h.stringify_keys
    runbook = Runbook.named(workspace.runbooks.active, given[RUNBOOK_ARG])
    return [] unless runbook&.workflow

    Conversation::Tools::RunWorkflow.plan_rows(workspace, Conversation::Tools::RunWorkflow::WORKFLOW_ARG => runbook.workflow.slug,
                                                          Conversation::Tools::RunWorkflow::INPUTS_ARG => given[INPUTS_ARG])
  end

  private

  def find(given) = Runbook.named(@turn.workspace.runbooks.active.includes(:runbook_steps), given[RUNBOOK_ARG])

  # Everything that would stop the run before any step, in words Halon can act on.
  def refusal_before_running(given)
    return "Say which runbook, by its name." if given[RUNBOOK_ARG].to_s.strip.empty?
    return "#{@turn.asker_name} may not read runbooks, so none can be run." unless reads_runbooks?

    runbook = find(given)
    return "No runbook is called #{given[RUNBOOK_ARG]}. search_runbooks lists them." unless runbook
    return "#{runbook.name} links no workflow, so a person follows it by hand. get_runbook shows its steps." unless runbook.workflow

    blocked = runbook.run_blocked_reason(@turn.asker)
    return [ blocked, ("Its page: #{Workflow::Links.page(runbook.workflow)}" unless runbook.workflow.live?) ].compact.join(" ") if blocked

    missing = Workflow::Trigger.resolve_inputs(runbook.workflow.live_version.trigger, given[INPUTS_ARG]).missing
    "Ask the person first: #{missing.map { |input| input['question'] }.join(' ')} Then call it again with #{INPUTS_ARG}." if missing.any?
  end

  def start_workflow(runbook, given, tool_call)
    workflow = runbook.workflow
    run = @turn.tool_call(action_key: Workflow::CREATE_KEY, params: { Conversation::Tools::RunWorkflow::WORKFLOW_ARG => workflow.slug }) do
      RunbookRunService.new(runbook).start!(by: @turn.asker, inputs: given[INPUTS_ARG].to_h, incident: @turn.incident,
                                            started_by_kind: Workflow::Run::STARTED_BY_HALON)
    end.value
    "Started #{workflow.name}, the workflow #{runbook.name} runs. Its run: #{Workflow::Links.run(run)}. Tell the person it is running and where they can follow it."
  rescue Workflow::Run::Refused => error
    refused(tool_call, error.message)
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    refused(tool_call, "#{@turn.asker_name} is not allowed to run workflows.")
  end

  def reads_runbooks? = @turn.asker.present? && @turn.asker.may?(Ability::Action::RESOURCE_RUNBOOKS, Ability::Action::ACTION_READ, @turn.workspace)

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    text
  end
end
