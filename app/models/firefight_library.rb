# What Firefight ships for a workspace to use as it is or copy, each item with a version. The versions live in
# config/library_versions.yml beside a digest of what each item says, so a test fails when an item changes without a new
# version, and bin/rails library:versions gives every changed item its next one. A workspace's copy remembers the version
# it was made from, which is how it learns a newer one exists.
module FirefightLibrary
  FILE = Rails.root.join("config/library_versions.yml")
  KIND_SKILLS = "skills".freeze
  KIND_WORKFLOWS = "workflows".freeze
  HEADER = "# Written by bin/rails library:versions. Each item's version goes up by one whenever what it says changes.\n".freeze

  Entry = Data.define(:version, :digest)

  module_function

  # Each kind's items as they are now, by name, as the digest of what each says.
  def sources = { KIND_SKILLS => -> { Chat::Skill.library_digests }, KIND_WORKFLOWS => -> { Workflow::Library.digests } }

  def version(kind, name) = recorded(kind)[name.to_s]&.version || 1

  def recorded(kind)
    @recorded ||= {}
    @recorded[kind] ||= read.fetch(kind, {}).to_h { |name, entry| [ name, Entry.new(version: entry.fetch("version"), digest: entry.fetch("digest")) ] }
  end

  # The items whose version is missing, out of date or names an item that is gone, as kind => names.
  def stale
    sources.to_h do |kind, digests|
      now = digests.call
      kept = recorded(kind)
      changed = now.reject { |name, digest| kept[name]&.digest == digest }.keys
      [ kind, (changed + (kept.keys - now.keys)).sort ]
    end.reject { |_kind, names| names.empty? }
  end

  def current? = stale.empty?

  # Gives each changed item its next version and each new one version 1, and drops what is gone.
  def write!
    document = sources.to_h do |kind, digests|
      kept = recorded(kind)
      entries = digests.call.sort.to_h do |name, digest|
        before = kept[name]
        version = if before.nil? then 1 elsif before.digest == digest then before.version else before.version + 1 end
        [ name, { "version" => version, "digest" => digest } ]
      end
      [ kind, entries ]
    end
    File.write(FILE, HEADER + document.to_yaml.delete_prefix("---\n"))
    reset!
  end

  def reset! = @recorded = nil

  def read = File.exist?(FILE) ? YAML.safe_load_file(FILE).to_h : {}
end
