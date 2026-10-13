# Adds a follow up to an incident (create_action_item), assigned to someone or not, and, when the step asks, opens its
# issue in the workspace's tracker (create_action_item_issue), each through the gateway as its own call. It changes
# something, so it needs its undo, such as deleting the follow up.
class DefinedWorkflow::Steps::CreateFollowUp < DefinedWorkflow::Steps::FirefightTool
  kind "create_follow_up"
  label "Create follow up"
  group GROUP_INCIDENT
  config_help "incident (its identifier), description (what needs doing, one line), member (who it is assigned to, by email, optional), " \
              "kind (followup, after the incident, or action, during it, followup by default), open_issue (true to open its issue in the " \
              "workspace's tracker too), undo. Outputs follow_up (its id), issue (its link, when one was opened), answer and data."

  KEY_DESCRIPTION = "description".freeze
  KEY_MEMBER = "member".freeze
  KEY_KIND = "kind".freeze
  KEY_OPEN_ISSUE = "open_issue".freeze
  OUTPUT_FOLLOW_UP = "follow_up".freeze
  OUTPUT_ISSUE = "issue".freeze
  ISSUE_TOOL = Mcp::Tools::CREATE_ACTION_ITEM_ISSUE

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  OUTPUT_DATA = DefinedWorkflow::Steps::CallTool::OUTPUT_DATA
  KEY_INCIDENT = DefinedWorkflow::Steps::FirefightTool::KEY_INCIDENT

  class << self
    def tool_for(_config, _workspace) = Mcp::Tools::CREATE_ACTION_ITEM

    def arguments_for(config, _workspace)
      { KEY_INCIDENT => config[KEY_INCIDENT].to_s, KEY_DESCRIPTION => config[KEY_DESCRIPTION].to_s,
        KEY_KIND => config[KEY_KIND].presence || IncidentAction::ACTION_TYPE_FOLLOWUP, KEY_MEMBER => config[KEY_MEMBER].presence }.compact
    end

    def opens_issue?(config) = ActiveModel::Type::Boolean.new.cast(config[KEY_OPEN_ISSUE]) == true

    def undoable?(_config, _workspace) = true

    def output_fields(_config) = [ OUTPUT_FOLLOW_UP, OUTPUT_ISSUE, OUTPUT_ANSWER, OUTPUT_DATA ]

    def reach(config, workspace)
      issue = opens_issue?(config) ? DefinedWorkflow::Reach.for_tool(workspace, ISSUE_TOOL, {}) : []
      (super + issue).uniq(&:key)
    end

    def own_problems(config, named, _workspace)
      found = [ needs(config, KEY_INCIDENT, named, "the incident it follows up, such as {{trigger.incident.identifier}}"),
                needs(config, KEY_DESCRIPTION, named, "what needs doing") ]
      kind = config[KEY_KIND].to_s
      found << "#{named} is a #{kind}, where it is followup or action." unless kind.empty? || IncidentAction::ACTION_TYPES.include?(kind)
      found.compact
    end

    def describe(config, _workspace)
      issue = opens_issue?(config) ? ", with its issue" : ""
      "On #{config[KEY_INCIDENT]}: #{config[KEY_DESCRIPTION].to_s.squish}#{issue}".truncate(200)
    end
  end

  private

  def handed_on(data) = { OUTPUT_FOLLOW_UP => data["id"] }

  # The follow up is made first. Its issue is a second call, which needs the follow up's id and is held or refused on
  # its own, and a refusal there leaves the follow up made, saying so.
  def call(approval_id)
    made = super
    return made if made.is_a?(SolidWorkflow::Park) || !self.class.opens_issue?(@config) || made[OUTPUT_FOLLOW_UP].blank?

    issue = open_issue(made[OUTPUT_FOLLOW_UP])
    made.merge(OUTPUT_ISSUE => issue)
  end

  def open_issue(follow_up)
    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    entry = Chat::Tools.catalog(agent_run).find { |found| found.name.to_s == ISSUE_TOOL }
    raise Refused, "The follow up was made, but #{@run.workflow.name} may not open its issue. An admin grants it on the workflow's page." unless entry&.tool

    answer = entry.tool.call(incident: @config[KEY_INCIDENT].to_s, action_item: follow_up)
    raise Failed, "The follow up was made, but its issue was not: #{(agent_run.raw.presence || answer).to_s.truncate(ANSWER_LIMIT)}" if agent_run.failed? || agent_run.held

    data = parsed(agent_run.raw.nil? ? answer.to_s : agent_run.raw.to_s)
    data.is_a?(Hash) ? data["external_url"] : nil
  end
end
