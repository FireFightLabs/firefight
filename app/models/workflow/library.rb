# Firefight's own workflows, kept as data in config/workflow_library/<key>.yml: a name, what it does, other names, and
# the trigger, steps, edges and outputs of a workflow version. Each carries a version (FirefightLibrary). A workspace
# uses one as it is, and moves with each new version while its steps stay Firefight's, or copies it, and is told when a
# newer one exists with what changed. An item whose steps the runtime cannot run yet is listed but cannot be taken.
module Workflow::Library
  DIRECTORY = Rails.root.join("config/workflow_library")

  Item = Data.define(:key, :name, :description, :aliases, :definition, :version) do
    def trigger = definition["trigger"]

    # Why it cannot be used here yet, as each sentence publishing it would be refused with.
    def problems = Workflow::Version.new(**definition.symbolize_keys).problems

    def available? = problems.empty?

    def digest = Digest::SHA256.hexdigest(definition.merge("name" => name, "description" => description, "aliases" => aliases).to_json)
  end

  module_function

  def all
    @all ||= Dir[DIRECTORY.join("*.yml")].sort.map { |path| parse(path) }.freeze
  end

  def find(key) = all.find { |item| item.key == key.to_s }

  # What each item says, by key, which its library version is kept against.
  def digests = all.to_h { |item| [ item.key, item.digest ] }

  def parse(path)
    key = File.basename(path, ".yml")
    data = YAML.safe_load_file(path)
    Item.new(
      key: key, name: data.fetch("name"), description: data.fetch("description"), aliases: Array(data["aliases"]),
      definition: data.slice(*Workflow::Version::CONTENT).reverse_merge("edges" => [], "outputs" => {}),
      version: FirefightLibrary.version(FirefightLibrary::KIND_WORKFLOWS, key)
    )
  end

  # Moves every workflow that follows an item on to the item's current version. Each moves in its own transaction, so
  # one that cannot is left as it was and logged, and the rest still move.
  def upgrade_all!
    all.each do |item|
      Workflow.where(library_key: item.key, follows_library: true).where("library_version < ?", item.version).find_each do |workflow|
        workflow.upgrade_from_library!
      rescue ActiveRecord::ActiveRecordError => error
        Rails.logger.error({ event: "workflow_library.upgrade_failed", workflow_id: workflow.id, library_key: item.key, version: item.version,
                             error: error.class.name, message: error.message })
      end
    end
  end
end
