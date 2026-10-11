# A large workspace's connections, added to every scenario when the bench runs with HALON_BENCH_BIG_WORKSPACE=on, so a
# replay asks Halon to pick among a few hundred tools as a real workspace does, where a scenario alone offers a handful.
# The tools come from definitions Firefight already keeps (config/halon_bench/_big_workspace.yml says which), written once
# to _big_workspace_tools.yml in an order its seed fixes, so every replay offers the same menu. None has an answer of its
# own: a call to one answers as any call a scenario did not script, so they add choice and never the answer. Each sits
# under its provider, so tool search, the held tools budget and the specialists treat it as they treat a live one.
module Conversation::BenchWorkspace
  SOURCES = Rails.root.join("config/halon_bench/_big_workspace.yml")
  TOOLS = Rails.root.join("config/halon_bench/_big_workspace_tools.yml")
  SWITCH = "HALON_BENCH_BIG_WORKSPACE".freeze
  FROM_PACK = "pack".freeze
  READ = "read".freeze
  CHANGE = "change".freeze
  # What a run's label says when it measured the big workspace.
  LABEL = "big workspace".freeze

  module_function

  ON = %w[on true 1].freeze

  def on? = ON.include?(ENV[SWITCH].to_s.strip.downcase)

  # The extra tools as a scenario offers them, less any the scenario offers itself, whose own definition and answers win.
  def offered_beside(bench_case)
    taken = bench_case.tools.map(&:name).to_set
    tools.reject { |tool| taken.include?(tool.name) }
  end

  def tools
    @tools ||= YAML.safe_load_file(TOOLS).map { |data| Conversation::BenchCase.tool_from(data) }.freeze
  end

  # A run that measured the big workspace says so in its label and its prompt version, so it is never compared with one
  # that did not as if they were the same.
  def label(given) = on? ? [ given.presence, LABEL ].compact.join(", ") : given

  def version(prompt_version) = on? ? "#{prompt_version}+big-#{Digest::SHA256.file(TOOLS).hexdigest.first(8)}" : prompt_version

  # Every provider's tools from where its sources say, in the order the seed fixes, as the file holds them.
  def build
    sources = YAML.safe_load_file(SOURCES)
    built = sources.fetch("providers").flat_map { |provider| from(provider) }
    names = built.map { |tool| tool["name"] }
    raise ArgumentError, "The big workspace names #{(names.tally.select { |_name, count| count > 1 }.keys).to_sentence} twice." unless names.uniq.size == names.size

    built.sort_by { |tool| tool["name"] }.shuffle(random: Random.new(sources.fetch("seed")))
  end

  def write! = File.write(TOOLS, "#{header}#{build.to_yaml.delete_prefix("---\n")}")

  def header
    "# Written by bin/rails halon:bench_big_workspace from _big_workspace.yml. Edit that file, never this one.\n"
  end

  def from(provider)
    key = provider.fetch("key")
    source = provider.fetch("from")
    return from_pack(key) if source == FROM_PACK
    return from_shared(key, source) if source.end_with?(".yml")

    from_list(key, Rails.root.join(source), only: provider["only"], changes: Array(provider["changes"]))
  end

  # A native pack's own tools, as its connection offers them by the name Halon calls them.
  def from_pack(key)
    Integrations::NativePack.for(key).tool_definitions.map do |definition|
      tool("#{key}_#{definition.name}", definition.description, key, reads: definition.read_only, parameters: definition.params_schema)
    end
  end

  # The bench's shared tools of that provider, as scenarios already offer them.
  def from_shared(key, path)
    YAML.safe_load_file(Rails.root.join(path)).filter_map do |name, data|
      data.except("live").merge("name" => name) if data["source"] == key
    end
  end

  # A hosted server's published list: each line a tool, then read, change or how it is reached, then its parameters.
  def from_list(key, path, only:, changes:)
    entry = IntegrationProvider.find(key)
    File.readlines(path).reject { |line| line.start_with?("#") || line.strip.empty? }.filter_map do |line|
      name, kind, *parameters = line.split
      next if only && kind != only

      local = Integrations::McpExecutor.local_name(name)
      reads = [ READ, CHANGE ].include?(kind) ? entry.reads?(local, declared: kind == READ) : changes.exclude?(name)
      properties = parameters.to_h { |parameter| [ parameter, { "type" => "string" } ] }
      tool("#{key}_#{local}", "#{entry.name}'s #{local.tr('_', ' ')}. It #{reads ? 'only reads' : 'can change something'}.", key, reads: reads,
           parameters: { "type" => "object", "properties" => properties })
    end
  end

  def tool(name, description, source, reads:, parameters:)
    { "name" => name, "description" => description.to_s.squish, "source" => source, (reads ? "reads" : "confirms") => true,
      "parameters" => parameters.to_h.deep_stringify_keys }
  end
end
