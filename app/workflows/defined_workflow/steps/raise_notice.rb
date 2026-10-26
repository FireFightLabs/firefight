# Raises a monitoring notice with the same noise control as Halon's checks: said once, and again only when it got
# worse or came back after a long time unseen. It is said in the channel of the team that owns the resource it is
# about, else the team that owns the workflow, else the workspace's monitoring channel. It is Firefight's own record, so
# it needs monitoring create, and nothing outside Firefight changes, so it has no undo.
class DefinedWorkflow::Steps::RaiseNotice < DefinedWorkflow::Steps::Base
  kind "raise_notice"
  label "Raise a notice"
  group GROUP_MESSAGES
  config_help "signal (one of #{Investigation::Notice::SIGNALS.join(', ')}), topic (the same each time for the same problem), summary, severity " \
              "(low, medium or high, may be a reference), due_on (YYYY-MM-DD, optional), resource (optional, by its id or name on the map, and said in words when it is not on it). Said once, and again only when worse."

  KEY_SIGNAL = "signal".freeze
  KEY_TOPIC = "topic".freeze
  KEY_SUMMARY = "summary".freeze
  KEY_SEVERITY = "severity".freeze
  KEY_DUE_ON = "due_on".freeze
  KEY_RESOURCE = "resource".freeze
  OUTPUT_RAISED = "raised".freeze
  OUTPUT_SAID = "said".freeze
  OUTPUT_NOTICE = "notice_id".freeze
  ACTION = Ability::Action.system_key(Ability::Action::RESOURCE_MONITORING, Ability::Action::ACTION_CREATE)

  class << self
    def changes?(_config, _workspace) = true

    def undoable?(_config, _workspace) = false

    # Said once and never taken back, so there is nothing to check first.
    def checks_first?(_config, _workspace) = false

    def output_fields(_config) = [ OUTPUT_RAISED, OUTPUT_SAID, OUTPUT_NOTICE ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs what the notice is about." if config[KEY_TOPIC].to_s.strip.empty?
      found << "#{named} needs what the notice says." if config[KEY_SUMMARY].to_s.strip.empty?
      signal = config[KEY_SIGNAL].to_s
      unless signal.empty? || referenced?(signal) || Investigation::Notice::SIGNALS.include?(signal)
        found << "#{named} raises a #{signal} notice, which is not a kind of notice."
      end
      severity = config[KEY_SEVERITY].to_s
      unless severity.empty? || referenced?(severity) || Investigation::Notice::SEVERITIES.include?(severity)
        found << "#{named} raises a notice that is #{severity}, where it is low, medium or high."
      end
      found
    end

    def referenced?(value) = Workflow::Version.references_in(value).any?

    def reach(_config, workspace, **)
      [ Ability::Action.lookup(ACTION, workspace), Ability::Action.lookup(Ability::Action::MAP_READ, workspace) ]
        .compact.map { |action| DefinedWorkflow::Reach::Needed.of_action(action) }
    end

    def describe(config, _workspace) = [ config[KEY_TOPIC], config[KEY_SUMMARY] ].compact_blank.join(": ").truncate(200)
  end

  def perform
    return simulated_output(self.class.describe(@config, workspace)) if simulated?

    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    # A notice is Firefight telling a team, like Halon's own checks, so no approval rule holds it.
    notice = agent_run.tool_call(action_key: ACTION, params: { KEY_TOPIC => reading.topic, KEY_SIGNAL => reading.signal }, holdable: false) do
      Investigation::Notice.observe!(workspace, reading, workflow_run: @run)
    end.value
    said = notice ? Investigation::NoticeDelivery.new(workspace).say!(notice, channel_id: notice_channel) : false
    { OUTPUT_RAISED => notice.present?, OUTPUT_SAID => said, OUTPUT_NOTICE => notice&.id }
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(ACTION)
  end

  private

  def reading
    @reading ||= Investigation::Notice::Reading.new(
      signal: @config[KEY_SIGNAL].to_s.presence_in(Investigation::Notice::SIGNALS) || Investigation::Notice::SIGNAL_OTHER,
      topic: @config[KEY_TOPIC].to_s, summary: @config[KEY_SUMMARY].to_s,
      severity: @config[KEY_SEVERITY].to_s.presence_in(Investigation::Notice::SEVERITIES) || Investigation::Notice::SEVERITY_LOW,
      due_on: due_on, resource: resource, resource_words: (resource_reference.presence unless resource)
    )
  end

  def resource_reference = @config[KEY_RESOURCE].to_s.strip

  def notice_channel = Investigation::Notice.channel_for(workspace, reading.resource, team: @run.workflow.owner_team)

  def due_on
    value = @config[KEY_DUE_ON].to_s
    value.present? ? Date.iso8601(value) : nil
  rescue Date::Error
    raise Refused, "#{@step.label} gives the day it becomes a problem as #{value}, which is not a date such as 2026-10-28."
  end

  # The resource on the map it is about. One not on the map is nil, and the notice names it in words instead.
  def resource
    return @resource if defined?(@resource)

    reference = resource_reference
    return @resource = nil if reference.blank?

    found = ResourceMap::Resource.visible_to(principal, workspace).referenced(workspace, reference).present.to_a
    raise Refused, "More than one resource is called #{reference}. Name it by its id on the map." if found.size > 1

    @resource = found.first
  end
end
