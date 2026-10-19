# A code fix whose right change is known, for measuring the code a coding agent writes against it: the incident it
# comes from, the brief Halon hands the agent, the files as they stood before the fix and the diff that fixes them.
# Written by hand with made up names, in config/halon_bench/code_fixes, a folder the chat bench does not read.
class CodeChange::BenchCase
  DIRECTORY = Conversation::BenchCase::DIRECTORY.join("code_fixes")

  class Invalid < StandardError; end

  attr_reader :key, :title, :shape, :repository, :brief, :files, :expected_diff, :expected

  def initialize(key:, title:, shape:, repository:, brief:, files:, expected_diff:)
    @key = key
    @title = title
    @shape = shape
    @repository = repository
    @brief = brief
    @files = files
    @expected_diff = expected_diff
    @expected = CodeChange::UnifiedDiff.parse(expected_diff)
  end

  def self.scenarios = Dir[DIRECTORY.join("*.yml")].sort.map { |path| from_file(path) }

  def self.scenario(key) = scenarios.find { |scenario| scenario.key == key } || raise(Invalid, "No code fix scenario is called #{key}.")

  def self.from_file(path)
    from_hash(YAML.safe_load_file(path), key: File.basename(path, ".yml"))
  rescue Invalid => error
    raise Invalid, "#{File.basename(path)}: #{error.message}"
  end

  def self.from_hash(data, key:)
    data = data.to_h.deep_stringify_keys
    new(
      key: key, title: required(data, "title"), shape: data["shape"].to_s.strip, repository: required(data, "repository"),
      brief: required(data, "brief").to_s.strip, files: required(data, "files").to_h.transform_keys(&:to_s), expected_diff: required(data, "expected_diff")
    ).tap(&:check!)
  end

  def self.required(data, field)
    data[field].presence || raise(Invalid, "#{field} is missing.")
  end
  private_class_method :required

  # The diff names only files the scenario holds, or new ones, and applies to them, so its score means something.
  def check!
    raise Invalid, "The expected diff changes nothing." if expected.empty?

    expected.each_value do |patch|
      next if patch.created
      raise Invalid, "The expected diff changes #{patch.path}, which files does not hold." unless files.key?(patch.path)

      stray = patch.hunks.find { |hunk| !CodeChange::UnifiedDiff.applies?(hunk, files[patch.path]) }
      raise Invalid, "The expected diff does not apply to #{patch.path}, since the lines of its hunk at line #{stray.start} are not in the file." if stray
    end
  end
end
