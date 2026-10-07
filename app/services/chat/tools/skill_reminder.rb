# Points the agent at the skills for a tool on the first call to it, when the chat has not loaded one. open_tools says
# the same as a group opens, but tools opened for an earlier question stay open, so a later one never passes through it.
# A skill whose steps the chat still holds is never named, and a skill already named in the chat is not named again.
class Chat::Tools::SkillReminder
  def self.for(agent_run, source:, handle:, tool_call_id:)
    return if tool_call_id.blank?

    chat = agent_run.chat
    chat && new(chat, agent_run.workspace).text(source, handle, tool_call_id)
  end

  def initialize(chat, workspace)
    @chat = chat
    @workspace = workspace
  end

  def text(source, handle, tool_call_id)
    covering = Chat::Skill.available_to(@workspace).select { |skill| skill.source == source && skill.tools.include?(handle) }
    return if covering.empty?

    calls = @chat.calls_in_play.order(:created_at, :id).includes(:result).to_a
    return if covering.any? { |skill| loaded(calls).include?(skill.name) }

    position = calls.index { |call| call.tool_call_id == tool_call_id }
    return unless position

    earlier = calls.first(position)
    fitting = covering.reject { |skill| named_before?(skill, earlier) }
    return if fitting.empty?

    "Skills with the steps for this tool, which this chat has not loaded. If one fits what the person asked, load it " \
      "with use_skill before going further:\n#{fitting.map { |skill| "#{skill.name}: #{skill.used_when}" }.join("\n")}"
  end

  private

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
      connections = Integration::Tool.in_workspace(@workspace).index_by(&:model_facing_name)
      calls.to_set do |call|
        tool = connections[call.name]
        tool ? [ tool.integration.provider, tool.name ] : [ Chat::Skill::SOURCE_FIREFIGHT, call.name ]
      end
    end
  end
end
