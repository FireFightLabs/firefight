# Sends a direct message as Firefight to a member, an incident's lead, whoever holds one of its roles, or whoever was
# paged or escalated to for it, with the run's data in it. It is Firefight's own post (channel_posts.create), so grants,
# approval rules and the activity log decide it as they decide Post to channel, once for everyone it reaches. A message
# people have read cannot be taken back, so it carries no undo.
class DefinedWorkflow::Steps::MessagePerson < DefinedWorkflow::Steps::PostToChannel
  kind "message_person"
  label "Message a person"
  group GROUP_MESSAGES

  KEY_TO = "to".freeze
  KEY_PERSON = "person".freeze
  KEY_ROLE = "role".freeze
  KEY_INCIDENT = "incident".freeze
  TO_PERSON = "person".freeze
  TO_LEAD = "lead".freeze
  TO_ROLE = "role".freeze
  TO_ON_CALL = "on_call".freeze
  TO = [ TO_PERSON, TO_LEAD, TO_ROLE, TO_ON_CALL ].freeze
  # Who needs an incident to be found.
  FROM_INCIDENT = [ TO_LEAD, TO_ROLE, TO_ON_CALL ].freeze
  OUTPUT_TOLD = "told".freeze

  config_help "to (#{TO.join(', ')}), person (an email, for person), incident (its identifier, for lead, role and on_call), role (an incident " \
              "role's slug, for role), message (markdown, may use references). on_call is whoever was paged or escalated to for the incident. " \
              "Outputs told (who it reached) and answer."

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  KEY_MESSAGE = DefinedWorkflow::Steps::PostToChannel::KEY_MESSAGE

  class << self
    def output_fields(_config) = [ OUTPUT_TOLD, OUTPUT_ANSWER ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      to = config[KEY_TO].to_s
      return [ "#{named} needs who it messages, one of #{TO.join(', ')}." ] unless TO.include?(to)

      found = []
      found << "#{named} needs the person it messages, by email." if to == TO_PERSON && config[KEY_PERSON].to_s.strip.empty?
      found << "#{named} needs the incident whose people it messages." if FROM_INCIDENT.include?(to) && config[KEY_INCIDENT].to_s.strip.empty?
      found << "#{named} needs the role whose holder it messages." if to == TO_ROLE && config[KEY_ROLE].to_s.strip.empty?
      found << "#{named} needs what it says." if config[KEY_MESSAGE].to_s.strip.empty?
      found << "#{named} says at most #{ChannelPostService::MESSAGE_LIMIT.to_fs(:delimited)} characters." if config[KEY_MESSAGE].to_s.length > ChannelPostService::MESSAGE_LIMIT
      found
    end

    def describe(config, _workspace)
      whom = case config[KEY_TO]
      when TO_PERSON then config[KEY_PERSON]
      when TO_LEAD then "the lead of #{config[KEY_INCIDENT]}"
      when TO_ROLE then "the #{config[KEY_ROLE]} of #{config[KEY_INCIDENT]}"
      when TO_ON_CALL then "whoever is on call for #{config[KEY_INCIDENT]}"
      end
      "To #{whom}: #{config[KEY_MESSAGE].to_s.squish}".truncate(200)
    end
  end

  def arguments = { KEY_TO => @config[KEY_TO].to_s, KEY_MESSAGE => @config[KEY_MESSAGE].to_s }

  private

  # One authorization for everyone it reaches, then a direct message each. A member Firefight cannot reach in chat is
  # left out and said, and nobody reached at all fails the step.
  def call(approval_id)
    members = recipients
    raise Refused, "There is nobody to message: #{nobody_words}." if members.empty?

    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    params = { KEY_TO => members.map(&:id), KEY_MESSAGE => @config[KEY_MESSAGE].to_s }
    told, missed = agent_run.tool_call(action_key: Ability::Action::CHANNEL_POST, params: params) do
      members.partition { |member| tell(member) }
    end.value
    raise Failed, "Firefight could not message #{missed.map(&:actor_display_name).to_sentence}." if told.empty?

    answer = missed.any? ? "Messaged #{names(told)}. Could not reach #{names(missed)}." : "Messaged #{names(told)}."
    { OUTPUT_TOLD => told.map(&:actor_display_name), OUTPUT_ANSWER => answer }
  rescue AbilityGateway::PendingApproval => pending
    wait_for(pending.approval)
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(Ability::Action::CHANNEL_POST)
  end

  def tell(member)
    ChannelPostService.new(workspace).tell!(member: member, message: @config[KEY_MESSAGE].to_s, by: principal)
    true
  rescue ChannelPostService::Refused
    false
  end

  def names(members) = members.map(&:actor_display_name).to_sentence

  def recipients
    case @config[KEY_TO]
    when TO_PERSON then [ workspace.workspace_memberships.resolve(@config[KEY_PERSON].to_s.strip, acting: principal) ].compact
    when TO_LEAD then [ incident&.lead ].compact
    when TO_ROLE then [ role && incident&.role_holder(role) ].compact
    when TO_ON_CALL then incident&.on_call_members.to_a
    else []
    end
  end

  def incident
    @incident ||= Mcp::Tools::GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), @config[KEY_INCIDENT].to_s)
  end

  def role = @role ||= workspace.incident_roles.find_by(slug: @config[KEY_ROLE].to_s)

  def nobody_words
    case @config[KEY_TO]
    when TO_PERSON then "no member is #{@config[KEY_PERSON]}"
    when TO_LEAD then incident ? "#{incident.identifier} has no lead" : "no incident is #{@config[KEY_INCIDENT]}"
    when TO_ROLE then incident ? "nobody holds #{@config[KEY_ROLE]} on #{incident.identifier}" : "no incident is #{@config[KEY_INCIDENT]}"
    else incident ? "nobody was paged or escalated to for #{incident.identifier}" : "no incident is #{@config[KEY_INCIDENT]}"
    end
  end
end
