# use_skill in a replay, serving the real skills as a live chat does: Firefight's own, and each provider's whose tools
# the scenario offers, as a workspace that connected it is offered them. Loading one says its steps, naming each tool
# as the scenario offers it, and makes the scenario's tools it names callable. A guide is read from the docs store as
# it is live, so a database that never read the provider's documentation answers as a fresh install does.
class Conversation::Rehearsal::UseSkill < Chat::Tools::UseSkill
  # tools are the scenario's tool definitions, open makes the named ones callable and returns them. reserved names the
  # specialist that holds a read, by its title, or nil, where the deployment asks specialists.
  def initialize(tools:, open:, reserved: ->(_name) { })
    super(nil, offer: nil)
    @tools = tools
    @open = open
    @reserved = reserved
  end

  def call(tool_call: nil, **arguments)
    given = arguments.stringify_keys
    skill = skills.find { |each| each.name == given["skill"].to_s }
    return "There is no skill called #{given['skill']}. The skills are: #{skills.map(&:name).join(', ')}." unless skill
    return guide(skill, given["reference"]) if given["reference"].present?

    entries = entries_for(skill)
    held, in_hand = entries.partition { |entry| @reserved.call(entry.name) }
    @open.call(in_hand.map(&:name))
    [ steps_for(skill, entries), guides(skill), specialists(held) ].compact.join("\n\n")
  end

  private

  def skills
    @skills ||= begin
      connected = @tools.select(&:outside?).map(&:source)
      Chat::Skill.all.select { |skill| skill.firefight? || connected.include?(skill.source) }
    end
  end

  # The scenario's tools the skill names, by the name the provider gives it or as the scenario calls it.
  def entries_for(skill)
    skill.tools.filter_map do |handle|
      tool = @tools.find { |each| each.name == handle || each.name == "#{skill.source}_#{handle}" }
      tool && Chat::Tools::Entry.new(name: tool.name, description: tool.description, state: Chat::Tools::STATE_READY, tool: nil,
                                     group: tool.group_key, source: tool.source, handle: handle)
    end
  end
end
