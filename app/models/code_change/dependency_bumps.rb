# A dependency change in plain words, "pg 1.4.0 to 1.5.0", read from a manifest or lockfile diff rather than shown as
# hundreds of changed lines. Formats it does not read are still listed as changed files, just without the versions.
module CodeChange::DependencyBumps
  Bump = Data.define(:name, :from, :to) do
    def to_s
      return "#{name} added at #{to}" if from.nil?
      return "#{name} removed (was #{from})" if to.nil?

      "#{name} #{from} to #{to}"
    end
  end

  # Each reads one line of a diff into a name and a version.
  READERS = {
    /(\A|\/)Gemfile\.lock\z/ => /\A {4}([A-Za-z0-9_.\-]+) \(([^)]+)\)\z/,
    /(\A|\/)package\.json\z/ => /\A\s+"(@?[A-Za-z0-9_.\-\/]+)":\s*"([^"]+)",?\z/,
    /(\A|\/)go\.mod\z/ => /\A\s*(?:require\s+)?([a-z0-9.\-]+\.[a-z]+\/\S+)\s+(v\S+)/,
    /(\A|\/)requirements[^\/]*\.txt\z/ => /\A([A-Za-z0-9_.\-\[\]]+)\s*==\s*(\S+)/
  }.freeze

  def self.from(path, patch)
    reader = READERS.find { |file, _line| path.to_s.match?(file) }&.last
    return [] unless reader && patch.present?

    removed = versions(patch, "-", reader)
    added = versions(patch, "+", reader)
    (removed.keys | added.keys).filter_map do |name|
      next if removed[name] == added[name]

      Bump.new(name: name, from: removed[name], to: added[name])
    end
  end

  def self.versions(patch, sign, reader)
    patch.each_line.with_object({}) do |line, found|
      next unless line.start_with?(sign) && !line.start_with?("#{sign * 3}")

      match = line[1..].chomp.match(reader)
      found[match[1]] = match[2] if match
    end
  end
  private_class_method :versions
end
