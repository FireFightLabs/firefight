# A short recipe for a common task in Firefight, read from config/skills. The agent sees each one's name and when to use
# it, and loads one when a question matches, which makes the tools it names callable and says the steps. So a declare
# does not spend calls opening groups and reading config the form already lists.
class Chat::Skill
  DIRECTORY = Rails.root.join("config/skills")
  FRONT_MATTER = /\A---\n(.*?)\n---\n(.*)\z/m

  Definition = Data.define(:name, :used_when, :tools, :steps)

  class << self
    def all
      @all ||= Dir[DIRECTORY.join("*.md")].sort.map { |path| parse(path) }.freeze
    end

    def find(name) = all.find { |skill| skill.name == name.to_s }

    def parse(path)
      header, steps = File.read(path).match(FRONT_MATTER)&.captures
      raise ArgumentError, "#{path} has no front matter" unless header

      meta = YAML.safe_load(header)
      Definition.new(name: meta.fetch("name"), used_when: meta.fetch("when"), tools: Array(meta.fetch("tools")), steps: steps.strip)
    end
  end
end
