# A short recipe for a common task, read from config/skills/<source>/<domain>/<name>.md. The source is whose tools the
# skill drives (firefight for Firefight's own) and the domain is the tool group it belongs to. The agent sees each one's
# name and when to use it, and loads one when a question matches, which makes the tools it names callable and says the
# steps. So a declare does not spend calls opening groups and reading config the form already lists.
class Chat::Skill
  DIRECTORY = Rails.root.join("config/skills")
  FRONT_MATTER = /\A---\n(.*?)\n---\n(.*)\z/m
  SOURCE_FIREFIGHT = "firefight".freeze

  Definition = Data.define(:name, :source, :domain, :used_when, :tools, :steps)

  class << self
    def all
      @all ||= Dir[DIRECTORY.join("*/*/*.md")].sort.map { |path| parse(path) }.freeze
    end

    def find(name) = all.find { |skill| skill.name == name.to_s }

    def parse(path)
      header, steps = File.read(path).match(FRONT_MATTER)&.captures
      raise ArgumentError, "#{path} has no front matter" unless header

      meta = YAML.safe_load(header)
      source, domain = Pathname(path).relative_path_from(DIRECTORY).each_filename.first(2)
      Definition.new(
        name: meta.fetch("name"), source: source, domain: domain, used_when: meta.fetch("when"),
        tools: Array(meta.fetch("tools")), steps: steps.strip
      )
    end
  end
end
