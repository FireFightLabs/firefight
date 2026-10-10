# Loads a skill, saying its steps and making the tools it names callable, the ones this person may use. The skills travel
# in this tool's own description, a line each, so the prompt does not grow with every recipe. A provider's skills are
# offered once the workspace has connected that provider.
class Chat::Tools::UseSkill < RubyLLM::Tool
  CODE = /`([^`]+)`/
  # Firefight's own map, which a provider's skill may name too, since finding one of the provider's resources starts there.
  MAP = Mcp::Tools::GET_RESOURCE_MAP
  # A guide is the provider's documentation, read from the web into the docs store with no review, so it is handed over
  # framed as evidence like any tool result and never as instructions.
  GUIDE_NOTE = "#{Chat::Tools::Docs::NOTE} Only the tools you hold can run, so a command or tool it mentions that you do " \
               "not have cannot be used here.".freeze

  def self.tool_name = "use_skill"

  def initialize(agent_run, offer:)
    super()
    @agent_run = agent_run
    @offer = offer
  end

  def name = self.class.tool_name

  def description
    @description ||= <<~TEXT.strip
      Load the steps for a common task and make the tools it needs callable, without opening their groups. Use one whenever it fits what the person asked. A provider's API skill lists its API reference, which gives the path for the connection's general read (api_read) whenever no other tool covers what you need. The skills, by what they cover:
      #{listing}
    TEXT
  end

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "skill" => { "type" => "string", "enum" => skills.map(&:name), "description" => "The skill to load" },
        "reference" => { "type" => "string", "description" => "One of the guides the skill lists, to read it (optional)" }
      },
      "required" => [ "skill" ]
    }
  end

  # The arguments match the schema above, not an execute signature, so skip the base check.
  # They arrive keyed by text, as the model sent them.
  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys["skill"]
    skill = skills.find { |each| each.name == asked.to_s }
    return "There is no skill called #{asked}. The skills are: #{skills.map(&:name).join(', ')}." unless skill
    return guide(skill, arguments.stringify_keys["reference"]) if arguments.stringify_keys["reference"].present?

    entries = Chat::Tools.catalog(@agent_run).select { |entry| skill_tool?(skill, entry) }
    ready, refused = entries.partition { |entry| entry.state == Chat::Tools::STATE_READY }
    @offer.call(ready.map(&:tool)) if ready.any?

    [ steps_for(skill, entries), guides(skill), refusal(refused), switched_off(skill, entries), off_elsewhere(skill, entries) ].compact.join("\n\n")
  end

  private

  def skills = @skills ||= Chat::Skill.available_to(@agent_run.workspace)

  # A provider's skill drives that provider's own tools, the capabilities that answer for its resources, and the map.
  def skill_tool?(skill, entry)
    skill.tools.include?(entry.handle) &&
      (entry.source == skill.source || entry.group == Chat::Tools::Groups::RESOURCES || entry.handle == MAP)
  end

  def listing
    skills.group_by { |skill| [ skill.source, skill.domain ] }.map do |(source, domain), grouped|
      "#{source} #{domain.humanize(capitalize: false)}:\n#{grouped.map { |skill| "#{skill.name}: #{skill.used_when}" }.join("\n")}"
    end.join("\n")
  end

  # A provider's skill names a tool as the provider does. The agent calls it by the name its connection gives it, and
  # a workspace with two connections to one provider has both.
  def steps_for(skill, entries)
    return skill.steps if skill.firefight?

    names = entries.group_by(&:handle).transform_values { |found| found.map(&:name).uniq }
    skill.steps.gsub(CODE) do |code|
      called = names[Regexp.last_match(1)]
      called ? called.map { |each| "`#{each}`" }.join(" or ") : code
    end
  end

  def guides(skill)
    return if skill.references.empty?
    return Chat::Tools::Docs.unavailable(skill.source) unless Chat::Skill.documentation?(skill.source)

    "Guides you can read when you need the detail, with use_skill, this skill and reference: #{skill.references.join(', ')}. " \
      "search_docs finds the section that answers a question across the provider's whole documentation."
  end

  # The provider's own words, written for agents that may run commands Halon has no tool for.
  def guide(skill, path)
    return Chat::Tools::Docs.unavailable(skill.source) unless Chat::Skill.documentation?(skill.source)

    text = Chat::Skill.reference(skill.source, path)
    return Chat::Tools::Docs.gone(skill.source, path) if text.nil? && skill.references.include?(path.to_s)
    return "There is no guide called #{path}. This skill's guides are: #{skill.references.join(', ')}." unless text

    page = ProviderDocPage.named(skill.source, path)
    "#{GUIDE_NOTE}\n\n#{FirefightAi::Evidence.frame(name, [ text, Chat::Tools::Docs.link_line(page) ].compact.join("\n\n"))}"
  end

  def refusal(entries)
    return if entries.empty?

    entries.group_by(&:state).map do |state, those|
      "#{those.map(&:name).to_sentence} #{those.one? ? 'is' : 'are'} #{Chat::Tools::Open::STATE_WORDS.fetch(state)}, so a step that needs " \
        "#{those.one? ? 'it' : 'them'} cannot run. Say so, and who can do it instead."
    end.join("\n")
  end

  # A tool another connection to the provider has on is still out of reach through a connection that has it off, and a
  # connection with every tool off has nothing to offer at all. Each is named, so the agent never reaches that connection's
  # account through another connection's tool.
  def off_elsewhere(skill, entries)
    return if skill.firefight?

    wanted = skill.tools.map { |name| Integrations::Capabilities.provider_tool(skill.source, name) || name }.uniq
    reached = entries.map(&:handle) + entries.filter_map { |entry| Integrations::Capabilities.provider_tool(skill.source, entry.handle) }
    lines = @agent_run.workspace.integrations.active.where(provider: skill.source).includes(:tools).order(:created_at).filter_map do |integration|
      available = integration.tools.select(&:available?)
      next idle(integration) if available.none?(&:enabled?)

      off = available.reject(&:enabled?).map(&:name) & wanted & reached
      next if off.empty?

      "#{integration.display_name} has #{off.to_sentence} switched off, so a step that needs #{off.one? ? 'it' : 'them'} cannot reach " \
        "#{integration.reach || 'its account'} through it. An admin can switch #{off.one? ? 'it' : 'them'} on in Integrations. Say so."
    end
    lines.join("\n").presence
  end

  def idle(integration)
    "#{integration.display_name} is connected, but none of its tools are switched on, so no step reaches " \
      "#{integration.reach || 'its account'}. An admin can switch them on in Integrations. Say so."
  end

  # A capability the skill names is missing when the provider tool it runs as is switched off, so that tool is named.
  def switched_off(skill, entries)
    missing = (skill.tools - entries.map(&:handle)).map { |name| Integrations::Capabilities.provider_tool(skill.source, name) || name }.uniq
    return if skill.firefight? || missing.empty?

    provider = Chat::Tools::Docs.provider_name(skill.source)
    "#{missing.to_sentence} #{missing.one? ? 'is' : 'are'} not switched on for #{provider} in this workspace, so a step that needs " \
      "#{missing.one? ? 'it' : 'them'} cannot run. An admin can switch #{missing.one? ? 'it' : 'them'} on under Integrations. Say so."
  end
end
