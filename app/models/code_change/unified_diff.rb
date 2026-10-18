# A unified diff read into the files it changes, each with its hunks, the way git and every code host write one. A
# blank line inside a hunk is a blank line of context, since editors strip the single space git writes there.
module CodeChange::UnifiedDiff
  NEW_FILE = "/dev/null".freeze
  CONTEXT = " ".freeze
  ADDED = "+".freeze
  REMOVED = "-".freeze

  # start is the line the hunk begins at in the file before the change. lines are each [kind, text].
  Hunk = Data.define(:start, :lines) do
    # The lines the file holds before the change, in order.
    def before = lines.filter_map { |kind, text| text if kind != ADDED }

    def changed = lines.reject { |kind, _text| kind == CONTEXT }
  end

  FilePatch = Data.define(:path, :created, :hunks) do
    def changed = hunks.flat_map(&:changed)
  end

  HUNK_HEADER = /\A@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@/

  # Each file the diff changes, by its path after the change.
  def self.parse(text)
    files = {}
    patch = nil
    hunk = nil
    old_path = nil
    text.to_s.each_line(chomp: true) do |line|
      if line.start_with?("--- ")
        old_path = line.delete_prefix("--- ").strip
      elsif line.start_with?("+++ ") && old_path
        new_path = line.delete_prefix("+++ ").strip
        # A deleted file's new side is /dev/null, so it is named by its old path.
        path = strip_side(new_path == NEW_FILE ? old_path : new_path)
        patch = files[path] = FilePatch.new(path: path, created: old_path == NEW_FILE, hunks: [])
        old_path = nil
        hunk = nil
      elsif patch && (header = line.match(HUNK_HEADER))
        hunk = Hunk.new(start: header[1].to_i, lines: [])
        patch.hunks << hunk
      elsif hunk && line.empty?
        hunk.lines << [ CONTEXT, "" ]
      elsif hunk && [ CONTEXT, ADDED, REMOVED ].include?(line[0])
        hunk.lines << [ line[0], line[1..] ]
      end
    end
    files.transform_values { |each| each.with(hunks: each.hunks.map { |part| trimmed(part) }) }
  end

  # Whether every hunk's lines before the change sit together in the file, in order.
  def self.applies?(hunk, content)
    wanted = hunk.before
    return true if wanted.empty?

    lines = content.to_s.lines(chomp: true)
    (0..(lines.size - wanted.size)).any? { |index| lines[index, wanted.size] == wanted }
  end

  def self.strip_side(path) = path.sub(%r{\A[ab]/}, "")
  private_class_method :strip_side

  # Blank lines after a hunk's last line are the space between files, not context.
  def self.trimmed(hunk)
    lines = hunk.lines.dup
    lines.pop while lines.last == [ CONTEXT, "" ]
    hunk.with(lines: lines)
  end
  private_class_method :trimmed
end
