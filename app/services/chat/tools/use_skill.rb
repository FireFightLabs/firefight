# Loads a skill: says its steps and makes the tools it names callable, the ones this person may use. The skills travel
# in this tool's own description, a line each, so the prompt does not grow with every recipe.
class Chat::Tools::UseSkill < RubyLLM::Tool
  def self.tool_name = "use_skill"

  def initialize(agent_run, offer:)
    super()
    @agent_run = agent_run
    @offer = offer
  end

  def name = self.class.tool_name

  def description
    @description ||= <<~TEXT.strip
      Load the steps for a common task and make the tools it needs callable, without opening their groups. Use one whenever it fits what the person asked. The skills, by what they cover:
      #{listing}
    TEXT
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "skill" => { "type" => "string", "enum" => Chat::Skill.all.map(&:name), "description" => "The skill to load" }
      },
      "required" => [ "skill" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    skill = Chat::Skill.find(arguments.stringify_keys["skill"])
    return "There is no skill called #{arguments.stringify_keys['skill']}. The skills are: #{Chat::Skill.all.map(&:name).join(', ')}." unless skill

    entries = Chat::Tools.catalog(@agent_run).select { |entry| skill.tools.include?(entry.name) }
    ready, refused = entries.partition { |entry| entry.state == Chat::Tools::STATE_READY }
    @offer.call(ready.map(&:tool)) if ready.any?

    [ skill.steps, refusal(refused) ].compact.join("\n\n")
  end

  private

  def listing
    Chat::Skill.all.group_by { |skill| [ skill.source, skill.domain ] }.map do |(source, domain), skills|
      "#{source} #{domain.humanize(capitalize: false)}:\n#{skills.map { |skill| "#{skill.name}: #{skill.used_when}" }.join("\n")}"
    end.join("\n")
  end

  def refusal(entries)
    return if entries.empty?

    "#{entries.map(&:name).to_sentence} #{entries.one? ? 'is' : 'are'} not granted to whoever you are acting as, so a step that needs " \
      "#{entries.one? ? 'it' : 'them'} cannot run. Say so, and who can do it instead."
  end
end
