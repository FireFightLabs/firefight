# A short recipe for a common task, read from config/skills/<source>/<domain>/<name>.md. The source is whose tools the
# skill drives (firefight for Firefight's own, else a provider's key) and the domain is the tool group it belongs to.
# Firefight's playbooks sit under their own domain: one area of the SRE job each, what good looks like and how to
# approach it, which the always on instructions name (FirefightAi::Manual::PLAYBOOK_NAMES).
# The agent sees each one's name and when to use it, and loads one when a question matches, which makes the tools it
# names callable and says the steps. So a declare does not spend calls opening groups and reading config the form
# already lists.
class Chat::Skill
  DIRECTORY = Rails.root.join("config/skills")
  FRONT_MATTER = /\A---\n(.*?)\n---\n(.*)\z/m
  SOURCE_FIREFIGHT = "firefight".freeze
  DOMAIN_PLAYBOOKS = "playbooks".freeze
  # A workspace's own skill written from scratch, which names its tools as Halon calls them (Chat::CustomSkill).
  SOURCE_WORKSPACE = "workspace".freeze
  DOMAIN_CUSTOM = "custom".freeze

  # A provider's skill names its tools as the provider does, and its domain is the provider's category. references are
  # pages of the provider's documentation in the docs store (ProviderDocPage), by their path within the provider. A skill
  # lists the ones that help it, and the agent reads one when it needs the detail.
  # signals are what a provider's skill reads for the monitoring module, such as cost, so a scheduled check knows which
  # connected provider can answer it and which cannot.
  SIGNAL_COST = "cost".freeze
  # A provider's skill that reads the security events its edge network reports, such as blocked and challenged requests,
  # which a look for probing reads beside the logs.
  SIGNAL_SECURITY_EVENTS = "security_events".freeze
  SIGNALS = [ SIGNAL_COST, SIGNAL_SECURITY_EVENTS ].freeze

  # version is the library's for Firefight's own skills and the version number of a workspace's own, which also carries
  # its record's id (custom_skill_id).
  Definition = Data.define(:name, :source, :domain, :used_when, :tools, :steps, :references, :signals, :version, :custom_skill_id) do
    def initialize(version: 1, custom_skill_id: nil, **) = super

    def firefight? = source == SOURCE_FIREFIGHT

    def workspace? = source == SOURCE_WORKSPACE

    def custom? = custom_skill_id.present?

    # A provider's skill names its tools as the provider does. Firefight's own and a workspace's name them as Halon calls them.
    def names_tools_as_called? = firefight? || workspace?

    def content = { "when" => used_when, "tools" => tools, "steps" => steps, "references" => references, "signals" => signals }

    def digest = Digest::SHA256.hexdigest(content.to_json)
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

    # What each of Firefight's skills says, by name, which its library version is kept against (FirefightLibrary).
    def library_digests = all.to_h { |skill| [ skill.name, skill.digest ] }

    # Every playbook's name and words, in a fixed order, which the version of Halon's prompts includes.
    def playbooks_text
      all.select { |skill| skill.firefight? && skill.domain == DOMAIN_PLAYBOOKS }.sort_by(&:name)
         .map { |skill| "#{skill.name}: #{skill.used_when}\n#{skill.tools.join(', ')}\n#{skill.steps}" }.join("\n\n")
    end

    # The skills that read a signal, and the providers that have one.
    def reading(signal) = all.select { |skill| skill.signals.include?(signal) }

    def providers_reading(signal) = reading(signal).map(&:source).uniq

    # The workspace's connected providers that have a skill reading a signal, with those skills, and those that have
    # none, by provider key, so a check and the page say the same about what Halon cannot see.
    Coverage = Data.define(:skills, :read, :unread)

    def coverage(workspace, signal)
      connected = workspace.integrations.active.distinct.pluck(:provider)
      skills = reading(signal).select { |skill| connected.include?(skill.source) }
      Coverage.new(skills: skills, read: skills.map(&:source).uniq, unread: connected - providers_reading(signal))
    end

    # Firefight's own, and each provider's once the workspace has connected it, then the workspace's own skills. A
    # workspace's copy of one of Firefight's skills keeps its name and is used in its place.
    def available_to(workspace)
      connected = workspace.integrations.active.distinct.pluck(:provider)
      reachable = ->(skill) { skill.names_tools_as_called? || connected.include?(skill.source) }
      library = all.select(&reachable)
      own = Chat::CustomSkill.definitions_for(workspace).select(&reachable)
      return library if own.empty?

      taken = own.map(&:name)
      library.reject { |skill| taken.include?(skill.name) } + own
    end

    # Firefight's skills a workspace can copy: its own, and each connected provider's.
    def library_for(workspace)
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
        tools: Array(meta.fetch("tools")), steps: steps.strip, references: Array(meta["references"]), signals: Array(meta["signals"]),
        version: FirefightLibrary.version(FirefightLibrary::KIND_SKILLS, meta.fetch("name"))
      )
    end
  end
end
