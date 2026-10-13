# Sends a direct message as Firefight to a member, an incident's lead, whoever holds one of its roles, or whoever was
# paged or escalated to for it, with the run's data in it. It is Firefight's own post (channel_posts.create), so grants,
# approval rules and the activity log decide it as they decide Post to channel, once for everyone it reaches. A message
# people have read cannot be taken back, so it carries no undo.
class DefinedWorkflow::Steps::MessagePerson < DefinedWorkflow::Steps::PostToChannel
  kind "message_person"
  label "Message a person"
  group GROUP_MESSAGES

  PEOPLE = DefinedWorkflow::Steps::People
  KEY_TO = PEOPLE::KEY_TO
  KEY_PERSON = PEOPLE::KEY_PERSON
  KEY_ROLE = PEOPLE::KEY_ROLE
  KEY_INCIDENT = PEOPLE::KEY_INCIDENT
  TO_PERSON = PEOPLE::TO_PERSON
  TO_LEAD = PEOPLE::TO_LEAD
  TO_ROLE = PEOPLE::TO_ROLE
  TO_ON_CALL = PEOPLE::TO_ON_CALL
  TO = PEOPLE::TO
  FROM_INCIDENT = PEOPLE::FROM_INCIDENT
  OUTPUT_TOLD = "told".freeze

  config_help "#{PEOPLE.help} message (markdown, may use references). Outputs told (who it reached) and answer."

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  KEY_MESSAGE = DefinedWorkflow::Steps::PostToChannel::KEY_MESSAGE

  class << self
    def output_fields(_config) = [ OUTPUT_TOLD, OUTPUT_ANSWER ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = PEOPLE.problems(config, named, "messages")
      return found unless TO.include?(config[KEY_TO].to_s)

      found << "#{named} needs what it says." if config[KEY_MESSAGE].to_s.strip.empty?
      found << "#{named} says at most #{ChannelPostService::MESSAGE_LIMIT.to_fs(:delimited)} characters." if config[KEY_MESSAGE].to_s.length > ChannelPostService::MESSAGE_LIMIT
      found
    end

    def describe(config, _workspace) = "To #{PEOPLE.whom(config)}: #{config[KEY_MESSAGE].to_s.squish}".truncate(200)
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

  def recipients = PEOPLE.recipients(workspace, @config, acting: principal)

  def nobody_words = PEOPLE.nobody_words(workspace, @config)
end
