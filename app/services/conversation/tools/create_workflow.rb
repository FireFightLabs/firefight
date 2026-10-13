# Writes a workflow the person asked for, such as "in 30 minutes check web" or "every weekday at 9:00 look through the
# logs for probing", after they confirmed it on the card, which shows when it runs, each step and what the workflow will
# be able to do. Confirmed by someone who may publish, it goes live with exactly those grants. Anyone else's waits as a
# draft, and the admins are asked to publish it. It runs as the workflow's own identity, never as the person.
class Conversation::Tools::CreateWorkflow < RubyLLM::Tool
  NAME = "create_workflow".freeze

  description "Make a workflow: something that runs on its own later, on a schedule, or by hand, such as \"in 30 minutes check web\", " \
              "\"every weekday at 9:00 look through the logs for probing\" or a release the team runs by name. Use it, never a plan, " \
              "for anything the person wants done at a later time or again and again. Prefer a template from the library when one " \
              "fits: check_later for a check at a later time (with reply_in_chat true to post the verdict back here), probing_scan " \
              "for the daily look for probing. Otherwise write its trigger and steps. Every change carries its undo and is followed " \
              "by a step that reads how it went. The person confirms it on a card before anything is made. It runs as its own " \
              "identity with only what an admin grants it, and a person who may not publish gets a draft and an admin is asked."

  def self.tool_name = NAME

  def initialize(turn)
    super()
    @turn = turn
  end

  def name = NAME

  def parameters_schema = requires_approval? ? Chat::Tools.with_intent(Workflow::Authoring.schema) : Workflow::Authoring.schema

  # Everything a workflow does later is confirmed first, by whoever asked.
  def requires_approval? = @turn.asker.present?

  def approval_resolver = Chat::Tools::Target.resolver(@turn) { |given| refusal_before(given).present? }

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys.except(*Chat::Tools::FOR_PERSON)
    refused = refusal_before(given)
    return refused(tool_call, refused) if refused

    workflow = @turn.tool_call(action_key: Workflow::CREATE_KEY, params: { "name" => given["name"].to_s }) { made(given) }.value
    said = publish_or_ask(workflow)
    Conversation::Workflows.moved!(workflow)
    "#{said} Its card is in this chat with Run now and Cancel, and its page: #{Workflow::Links.page(workflow)}"
  rescue Workflow::Authoring::Refused => error
    refused(tool_call, "Nothing was made. #{error.message} Fix it and call create_workflow again.")
  rescue AbilityGateway::Denied, AbilityGateway::PendingApproval
    refused(tool_call, "#{@turn.asker_name} is not allowed to make workflows.")
  end

  # What the confirmation shows under the question: when it runs, each step and what it will be able to do, read from
  # what would be made rather than Halon's words about it.
  def self.plan_rows(workspace, arguments)
    preview = Workflow::Authoring.preview(workspace: workspace, spec: arguments.to_h.deep_stringify_keys)
    return [ [ "It cannot be made", preview.problem ] ] if preview.problem

    [ [ "Runs", preview.when ], *preview.steps.map { |step| [ step.first, step.last ] },
      (preview.reach.any? ? [ "It will be able to", preview.reach.to_sentence ] : nil) ].compact
  end

  # A timed trigger or a template given without a time zone takes the asker's, kept with the call when it is asked, so
  # the card and what is made read its time the same way.
  def self.settled_arguments(agent_run, arguments)
    templated = arguments[Workflow::Authoring::KEY_TEMPLATE].present?
    key = templated ? Workflow::Authoring::KEY_PARAMS : Workflow::Authoring::KEY_TRIGGER
    given = arguments[key].to_h
    zoned = templated || Workflow::Trigger::Schedule.timed?(given)
    zone_key = templated ? Workflow::Library::PARAM_TIME_ZONE : Workflow::Trigger::Schedule::KEY_TIME_ZONE
    return arguments unless zoned && given[zone_key].blank? && agent_run.asker.is_a?(WorkspaceMembership)

    zone = Conversation::Plans.time_zone_of(agent_run.asker, agent_run.workspace)
    zone ? arguments.merge(key => given.merge(zone_key => zone)) : arguments
  end

  private

  def made(given)
    zone = Conversation::Plans.time_zone_of(@turn.asker, @turn.workspace) if @turn.asker.is_a?(WorkspaceMembership)
    Workflow::Authoring.create!(workspace: @turn.workspace, spec: given, by: (@turn.asker if @turn.asker.is_a?(WorkspaceMembership)), halon: true,
                                reason: "#{@turn.asker_name} asked for it in a chat.", time_zone: zone, origin_conversation: @turn.conversation)
  end

  def publish_or_ask(workflow)
    draft = workflow.draft
    service = WorkflowPublishService.new(workflow)
    return "Made #{workflow.name} as a draft. #{service.ask_or_leave!(draft, by: @turn.asker).words}" unless service.may_publish?(draft, by: @turn.asker)

    result = service.publish_through_gateway!(draft, principal: @turn.asker, source: AbilityGateway::SOURCE_CONVERSATION)
    return "Made #{workflow.name} as a draft. #{result.words}" if result.words == WorkflowPublishService::PUBLISH_HELD
    return "Made #{workflow.name} as a draft, but it was not published. #{result.words}" unless result.ok

    "Made and published #{workflow.name}. It runs #{workflow.reload.trigger_words.downcase_first}#{next_words(workflow)}. Tell the person in a sentence."
  end

  def next_words(workflow) = workflow.next_run_at ? ", next at #{workflow.next_run_at.in_time_zone(workflow.time_zone || 'UTC').strftime('%H:%M on %A %-d %B')}" : ""

  # Everything that stops it before anything is made, in words Halon can act on.
  def refusal_before(given)
    return "Workflows are made for a person, and nobody is asking in this chat." unless @turn.asker
    return "Give the workflow its steps, or a template from the library." if given["template"].blank? && Array(given["steps"]).empty?

    Workflow::Authoring.preview(workspace: @turn.workspace, spec: given).problem
  end

  def refused(tool_call, text)
    Chat::Tools.mark_failed(@turn, tool_call&.id)
    text
  end
end
