# Points the agent at the skills for a tool on the first call to it, when the chat has not loaded one. open_tools says
# the same as a group opens, but tools opened for an earlier question stay open, so a later one never passes through it.
# A skill whose steps the chat still holds is never named, and a skill already named in the chat is not named again.
# A turn reads the skills and the connection tools with its catalogue, and the chat's calls once (Calls), rather than
# each again for every call it makes.
class Chat::Tools::SkillReminder
  # What a turn keeps the chat's calls under.
  KEPT_AS = :skill_reminder_calls

  def self.for(agent_run, source:, handle:, tool_call_id:)
    return if tool_call_id.blank?

    chat = agent_run.chat
    chat && new(chat, agent_run).text(source, handle, tool_call_id)
  end

  def initialize(chat, agent_run)
    @chat = chat
    @agent_run = agent_run
  end

  def text(source, handle, tool_call_id)
    covering = Chat::Tools.skills(@agent_run).select { |skill| skill.source == source && skill.tools.include?(handle) }
    return if covering.empty?

    calls = calls_in_play
    return if covering.any? { |skill| loaded(calls).include?(skill.name) }

    position = calls.index { |call| call.tool_call_id == tool_call_id }
    return unless position

    earlier = calls.first(position)
    fitting = covering.reject { |skill| named_before?(skill, earlier) }
    return if fitting.empty?

    "Skills with the steps for this tool, which this chat has not loaded. If one fits what the person asked, load it " \
      "with use_skill before going further:\n#{fitting.map { |skill| "#{skill.name}: #{skill.used_when}" }.join("\n")}"
  end

  # The chat's calls the model still sees, in the order they were made, with their results. Read whole the first time, and
  # after that only the calls made, answered or whose answer changed since, read whole again once their number says one
  # was put away or removed.
  class Calls
    # A call written while the last read ran is read again rather than missed.
    OVERLAP = 2.seconds

    def initialize(chat)
      @chat = chat
      @reading = Mutex.new
    end

    # A turn's reads run together, so one reads at a time.
    def all
      @reading.synchronize do
        @rows.nil? ? read_whole : read_since
        @rows.values.sort_by { |call| [ call.created_at, call.id ] }
      end
    end

    private

    def read_whole
      @read_at = Time.current
      @rows = @chat.calls_in_play.includes(:result).index_by(&:id)
    end

    def read_since
      since = @read_at - OVERLAP
      @read_at = Time.current
      answered = @chat.messages.where(updated_at: since..).select(:id)
      @chat.calls_in_play.where(updated_at: since..).or(@chat.calls_in_play.where(result_id: answered)).includes(:result).each { |call| @rows[call.id] = call }
      read_whole unless @chat.calls_in_play.count == @rows.size
    end
  end

  private

  def calls_in_play
    reading = @agent_run.is_a?(Conversation::Turn) ? @agent_run.kept(KEPT_AS) { Calls.new(@chat) } : Calls.new(@chat)
    reading.all
  end

  def loaded(calls)
    @loaded ||= calls.select { |call| call.name == Chat::Tools::UseSkill.tool_name }.filter_map { |call| call.arguments.to_h["skill"] }
  end

  # Named once a call used one of its tools, whose result carried this reminder, or once open_tools listed it.
  def named_before?(skill, earlier)
    used = handles(earlier)
    return true if skill.tools.any? { |tool| used.include?([ skill.source, tool ]) }

    earlier.any? { |call| call.name == Chat::Tools::Open.tool_name && call.result&.content.to_s.include?("#{skill.name}: ") }
  end

  # A connection's tool is called by its model facing name and a skill names it as the provider does. Firefight's own
  # tools are called by the name a skill uses.
  def handles(calls)
    @handles ||= begin
      connections = Chat::Tools.switched_on_tools(@agent_run).index_by(&:model_facing_name)
      calls.to_set do |call|
        tool = connections[call.name]
        tool ? [ tool.integration.provider, tool.name ] : [ Chat::Skill::SOURCE_FIREFIGHT, call.name ]
      end
    end
  end
end
