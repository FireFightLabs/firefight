# A short recipe for a common task, read from config/skills/<source>/<domain>/<name>.md. The source is whose tools the
# skill drives (firefight for Firefight's own, else a provider's key) and the domain is the tool group it belongs to.
# The agent sees each one's name and when to use it, and loads one when a question matches, which makes the tools it
# names callable and says the steps. So a declare does not spend calls opening groups and reading config the form
# already lists.
class Chat::Skill
  DIRECTORY = Rails.root.join("config/skills")
  FRONT_MATTER = /\A---\n(.*?)\n---\n(.*)\z/m
  SOURCE_FIREFIGHT = "firefight".freeze

  # A provider's skill names its tools as the provider does, and its domain is the provider's category. references are
  # pages of the provider's documentation in the docs store (ProviderDocPage), by their path within the provider. A skill
  # lists the ones that help it, and the agent reads one when it needs the detail.
  Definition = Data.define(:name, :source, :domain, :used_when, :tools, :steps, :references) do
    def firefight? = source == SOURCE_FIREFIGHT
  end

  class << self
    def all
      @all ||= Dir[DIRECTORY.join("*/*/*.md")].sort.map { |path| parse(path) }.freeze
    end

    # Every page of a source's documentation the docs store holds, by its path.
    def references_of(source) = ProviderDocPage.paths_of(source)

    # The page, with where it came from first so whatever is used from it is cited to its source, or nil when the store
    # does not hold it. Only a page the store holds can be named, so nothing else can be read.
    def reference(source, path)
      page = ProviderDocPage.named(source, path)
      page && "#{page.attribution}\n\n#{page.content}"
    end

    # Whether the source's documentation has been read into the store at all, so a missing page is told apart from
    # documentation that is not available here yet, such as on a fresh install with no network.
    def documentation?(source) = ProviderDocSource.read_for?(source)

    # Every guide a skill lists that its provider's documentation, once read, does not hold, as skill => paths.
    def missing_references
      all.select { |skill| skill.references.any? && documentation?(skill.source) }.to_h do |skill|
        [ skill.name, skill.references - references_of(skill.source) ]
      end.reject { |_name, paths| paths.empty? }
    end

    def find(name) = all.find { |skill| skill.name == name.to_s }

    # Firefight's own, and each provider's once the workspace has connected it.
    def available_to(workspace)
      connected = workspace.integrations.active.distinct.pluck(:provider)
      all.select { |skill| skill.firefight? || connected.include?(skill.source) }
    end

    def parse(path)
      header, steps = File.read(path).match(FRONT_MATTER)&.captures
      raise ArgumentError, "#{path} has no front matter" unless header

      meta = YAML.safe_load(header)
      source, domain = Pathname(path).relative_path_from(DIRECTORY).each_filename.first(2)
      Definition.new(
        name: meta.fetch("name"), source: source, domain: domain, used_when: meta.fetch("when"),
        tools: Array(meta.fetch("tools")), steps: steps.strip, references: Array(meta["references"])
      )
    end
  end
end
