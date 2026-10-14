# Posts a message as Firefight, with the run's data in it, in a channel the step names, or back where the workflow was
# asked for when Halon made it from a chat: that thread, or the direct messages of the person whose chat it was. It is
# Firefight's own post_to_channel, so it needs channel_posts.create, approval rules hold it and the activity log keeps
# it. A message people have read cannot be taken back, so it carries no undo, and it changes nothing a freeze or a read
# first protects.
class DefinedWorkflow::Steps::PostToChannel < DefinedWorkflow::Steps::CallTool
  kind "post_to_channel"
  label "Post to channel"
  group GROUP_MESSAGES
  config_help "channel (such as #ops) or reply_in_chat true to post back where it was asked for, message (markdown, may use references). " \
              "Outputs channel and link."

  KEY_CHANNEL = "channel".freeze
  KEY_MESSAGE = "message".freeze
  KEY_REPLY = "reply_in_chat".freeze
  OUTPUT_CHANNEL = "channel".freeze
  OUTPUT_LINK = "link".freeze
  TOOL = Mcp::Tools::POST_TO_CHANNEL

  class << self
    def changes?(_config, _workspace) = true

    def checks?(_config, _workspace) = false

    def undoable?(_config, _workspace) = false

    # Said once and never taken back, so there is nothing to check first.
    def checks_first?(_config, _workspace) = false

    def output_fields(_config) = [ OUTPUT_CHANNEL, OUTPUT_LINK, DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER ]

    def reply?(config) = ActiveModel::Type::Boolean.new.cast(config[KEY_REPLY]) == true

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs the channel it posts in, or to post back in the chat it came from." if config[KEY_CHANNEL].to_s.strip.empty? && !reply?(config)
      found << "#{named} needs what it posts." if config[KEY_MESSAGE].to_s.strip.empty?
      found << "#{named} posts at most #{ChannelPostService::MESSAGE_LIMIT.to_fs(:delimited)} characters." if config[KEY_MESSAGE].to_s.length > ChannelPostService::MESSAGE_LIMIT
      found
    end

    def reach(_config, workspace)
      action = Ability::Action.lookup(Ability::Action::CHANNEL_POST, workspace)
      action ? [ DefinedWorkflow::Reach::Needed.of_action(action) ] : []
    end

    def describe(config, _workspace)
      where = reply?(config) ? "back in the chat" : config[KEY_CHANNEL]
      "#{where}: #{config[KEY_MESSAGE].to_s.squish}".truncate(200)
    end
  end

  def tool_name = TOOL

  def arguments = { KEY_CHANNEL => @config[KEY_CHANNEL].to_s, KEY_MESSAGE => @config[KEY_MESSAGE].to_s }

  def frozen = nil

  private

  def output_of(said)
    data = parsed(said)
    data = {} unless data.is_a?(Hash)
    { OUTPUT_CHANNEL => data[KEY_CHANNEL], OUTPUT_LINK => data[OUTPUT_LINK], OUTPUT_ANSWER => said }
  end

  def call(approval_id)
    return super unless self.class.reply?(@config)

    reply(approval_id)
  end

  # Back where it was asked for, as Firefight's own post, authorized like any post.
  def reply(approval_id)
    conversation = @run.workflow.origin_conversation
    raise Refused, "#{@run.workflow.name} was not made from a chat, so there is nowhere to post back to." unless conversation

    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    posted = agent_run.tool_call(action_key: Ability::Action::CHANNEL_POST, params: { KEY_REPLY => true, KEY_MESSAGE => @config[KEY_MESSAGE].to_s }) do
      ChannelPostService.new(workspace).reply!(conversation: conversation, message: @config[KEY_MESSAGE].to_s, by: principal)
    end.value
    { OUTPUT_CHANNEL => posted.channel_name.presence || posted.channel_id, OUTPUT_LINK => posted.link, OUTPUT_ANSWER => "Posted." }
  rescue AbilityGateway::PendingApproval => pending
    wait_for(pending.approval)
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(Ability::Action::CHANNEL_POST)
  rescue ChannelPostService::Refused => refused
    raise Failed, refused.message
  end
end
