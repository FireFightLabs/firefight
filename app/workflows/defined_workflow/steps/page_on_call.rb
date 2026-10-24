# Wakes whoever is on call for an incident. With an on-call tool connected it reads who is on call there first, as the
# workflow's own identity, then raises a page through it (page_on_call), kept in step with the incident as any page is.
# Without one it escalates to the member the step names (escalate_incident), who is asked in chat and chased until they
# acknowledge. A page once raised has reached a person and cannot be taken back, so it carries no undo.
class DefinedWorkflow::Steps::PageOnCall < DefinedWorkflow::Steps::FirefightTool
  kind "page_on_call"
  label "Page on call"
  group GROUP_INCIDENT
  config_help "incident (its identifier), reason (what the person paged needs to know), target (what to page in the on-call tool, such as a " \
              "service or team there), tool (the on-call connection, only when there are several), person (who to page, by email, optional), " \
              "escalate_to (a member's email, who is escalated to when no on-call tool is connected). Outputs on_call (who the tool has on call), " \
              "paged, answer and data."

  KEY_REASON = "reason".freeze
  KEY_TARGET = "target".freeze
  KEY_TOOL = "tool".freeze
  KEY_PERSON = "person".freeze
  KEY_ESCALATE_TO = "escalate_to".freeze
  OUTPUT_ON_CALL = "on_call".freeze
  OUTPUT_PAGED = "paged".freeze
  # How many people a read of who is on call hands on.
  ON_CALL_LIMIT = 10

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  OUTPUT_DATA = DefinedWorkflow::Steps::CallTool::OUTPUT_DATA
  KEY_INCIDENT = DefinedWorkflow::Steps::FirefightTool::KEY_INCIDENT

  class << self
    def paging?(config, workspace) = workspace.paging_connection(config[KEY_TOOL]).present?

    def tool_for(config, workspace) = paging?(config, workspace) ? FirefightTools::PAGE_ON_CALL : FirefightTools::ESCALATE_INCIDENT

    def arguments_for(config, workspace)
      incident = { KEY_INCIDENT => config[KEY_INCIDENT].to_s, KEY_REASON => config[KEY_REASON].to_s }
      return incident.merge("member" => config[KEY_ESCALATE_TO].to_s) unless paging?(config, workspace)

      incident.merge(config.slice(KEY_TARGET, KEY_TOOL, KEY_PERSON).compact_blank)
    end

    def undoable?(_config, _workspace) = false

    def output_fields(_config) = [ OUTPUT_ON_CALL, OUTPUT_PAGED, OUTPUT_ANSWER, OUTPUT_DATA ]

    # Paging needs the change, and reading who is on call the on-call connection's reads.
    def reach(config, workspace, **)
      integration = workspace.paging_connection(config[KEY_TOOL])
      reads = integration ? [ DefinedWorkflow::Reach.read_pack(integration.id) ].compact.map { |role| DefinedWorkflow::Reach::Needed.of_role(role) } : []
      (super + reads).uniq(&:key)
    end

    def own_problems(config, named, workspace)
      found = [ needs(config, KEY_INCIDENT, named, "the incident it pages for, such as {{trigger.incident.identifier}}"),
                needs(config, KEY_REASON, named, "what the person paged needs to know") ]
      connections = Integrations::Paging.connections(workspace)
      if connections.any?
        found << needs(config, KEY_TARGET, named, "what to page in the on-call tool")
        found << "#{named} needs which on-call tool it pages through, one of #{connections.map(&:slug).join(', ')}." unless paging?(config, workspace)
      else
        found << needs(config, KEY_ESCALATE_TO, named, "who to escalate to, since no on-call tool is connected")
      end
      found.compact
    end

    def describe(config, workspace)
      whom = paging?(config, workspace) ? config[KEY_TARGET] : config[KEY_ESCALATE_TO]
      "Pages #{whom} for #{config[KEY_INCIDENT]}: #{config[KEY_REASON].to_s.squish}".truncate(200)
    end
  end

  def perform
    @on_call = on_call_now
    super
  end

  private

  def output_of(said)
    output = super
    output.merge(OUTPUT_ON_CALL => @on_call, OUTPUT_PAGED => @config[KEY_PERSON].presence || @config[KEY_TARGET].presence || @config[KEY_ESCALATE_TO])
  end

  def simulated_output(would) = super.merge(OUTPUT_ON_CALL => @on_call)

  # Who the on-call tool has on call now, read as the workflow's own identity, or nobody when there is no such tool or it
  # could not be read, which never stops the page.
  def on_call_now
    integration = workspace.paging_connection(@config[KEY_TOOL])
    return [] unless integration

    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    pager = Integrations::Paging.session(integration) do |tool, arguments, &run|
      agent_run.tool_call(action_key: tool.action_key, params: arguments, holdable: false) { run.call }.value
    end
    people = pager.on_call.first(ON_CALL_LIMIT).map { |person| { "name" => person.name, "email" => person.email, "covers" => person.covers }.compact }
    people
  rescue Integrations::Error, AbilityGateway::Denied, AbilityGateway::PendingApproval
    []
  end
end
