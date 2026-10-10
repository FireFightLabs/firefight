module Integrations
  module Packs
    # What every code host's pack shares: reading code in the run's sandbox (Code), reading infrastructure defined as
    # code (Infrastructure), and how a path, a ref and a time are taken from what the agent passed. A host's own pack
    # includes it and talks to its own API.
    module CodeHost
      PATH_FORMAT = /\A[^\/\0][^\0]*\z/
      # Refused in the executor, not the prompt. Prompts can be talked around.
      SENSITIVE_PATHS = /\.env|credential|secret|\.pem\z|\.key\z|id_rsa|id_ed25519|\.p12\z|\.pfx\z/i
      # A diff shows a file that may hold secrets by name only.
      WITHHELD_PATCH = "(not shown, since the file may hold secrets)".freeze
      GIT_FILE = /\Adiff --git /
      REF_FORMAT = %r{\A[\w.\-/]+\z}
      LINE_LIMIT = 200
      CONTEXT_LINES = 10
      # A build log is read from its end, where a job says why it failed.
      LOG_LINES = 200
      MAX_LOG_LINES = 1_000
      ANSI = /\e\[[0-9;?]*[A-Za-z]|\e\][^\a]*\a/
      # GitLab marks a log's collapsible sections with lines such as section_start:1700000000:build_script, which say nothing.
      SECTION_MARK = /\A\s*section_(start|end):\d+:[\w.\-]+(\[[^\]]*\])?/
      REGEX_TIMEOUT = 1
      # A deploy target that looks like production, when none is named.
      PRODUCTION = /\Aprod/i
      LOG_RANGE = {
        "minutes" => { "type" => "integer", "description" => "Only within this many minutes back from now (optional)" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze
      # The longest a log search looks back, a week, as a capability does.
      LOG_RANGE_MINUTES = 7 * 24 * 60
      LOG_FILTER = {
        "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
        "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
        "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
        "limit" => { "type" => "integer", "description" => "At most this many lines, from the end (optional, #{LOG_LINES}, at most #{MAX_LOG_LINES})" }
      }.freeze

      private

      def path_argument(arguments)
        path = arguments["path"].to_s
        fail! "path must be a relative path inside the repository" unless path.match?(PATH_FORMAT) && !path.include?("..")
        fail_policy! "Firefight does not read files that may hold secrets, such as .env files, keys and credentials, so #{path} is not read." if path.match?(SENSITIVE_PATHS)

        path
      end

      # A host's own diff of one file, left out when the file may hold secrets.
      def shown_patch(path, patch) = path.to_s.match?(SENSITIVE_PATHS) ? WITHHELD_PATCH : patch

      # git's own diff output, with each file that may hold secrets kept by its header line and its patch left out.
      def without_sensitive_patches(text)
        withheld = false
        text.to_s.each_line.filter_map do |line|
          if line.match?(GIT_FILE)
            withheld = line.match?(SENSITIVE_PATHS)
            next withheld ? "#{line.chomp}\n#{WITHHELD_PATCH}\n" : line
          end
          line unless withheld
        end.join
      end

      def ref_argument(arguments, key = "ref", required: false)
        ref = arguments[key].to_s.strip
        fail! "#{key} is required" if ref.blank? && required
        return nil if ref.blank?
        fail! "#{key} must be a commit SHA, branch or tag" unless ref.match?(REF_FORMAT) && !ref.include?("..")

        ref
      end

      def time_argument(arguments, key)
        Time.iso8601(arguments[key].to_s)
      rescue ArgumentError
        fail! "#{key} must be an ISO 8601 time, for example 2026-09-12T09:00:00Z"
      end

      # Time.zone.parse accepts "last tuesday" and would filter on a window the caller never gave.
      def since_argument(arguments, key = "since")
        raw = arguments[key].to_s
        return nil if raw.blank?

        Time.iso8601(raw)
      rescue ArgumentError
        fail! "#{key} must be an ISO 8601 time, for example 2026-09-12T09:00:00Z"
      end

      # The lines asked for with some around them, never more than LINE_LIMIT, or the top of the file.
      def slice_range(arguments, total)
        from = Integer(arguments["start_line"].to_s, exception: false)
        to = Integer(arguments["end_line"].to_s, exception: false) || from
        return [ 1, [ total, LINE_LIMIT ].min ] unless from

        from = (from - CONTEXT_LINES).clamp(1, total)
        to = (to + CONTEXT_LINES).clamp(from, total)
        to = [ to, from + LINE_LIMIT - 1 ].min
        [ from, to ]
      end

      def line_range!(arguments)
        from = Integer(arguments["start_line"].to_s, exception: false)
        to = Integer(arguments["end_line"].to_s, exception: false)
        fail! "start_line and end_line must be integers" unless from && to
        fail! "line range must be ascending and at most #{LINE_LIMIT} lines" unless from <= to && (to - from) < LINE_LIMIT

        [ from, to ]
      end

      # What a comparison changed, as a code host's files: filename, status, additions, deletions and patch.
      def grouped_files(files)
        groups = files.group_by { |file| CodeChange.kind_for(file["filename"]) }
        sections = CodeChange::KINDS.filter_map do |kind|
          next unless groups[kind]

          listed = groups[kind].map { |file| "  #{file['filename']} (#{file['status']}, +#{file['additions']} -#{file['deletions']})" }
          "#{CodeChange::KIND_LABELS.fetch(kind)}:\n#{listed.join("\n")}"
        end
        "Changed files, most likely to matter first:\n#{sections.join("\n")}"
      end

      def dependency_text(files)
        bumps = files.flat_map { |file| CodeChange::DependencyBumps.from(file["filename"], file["patch"]) }
        return nil if bumps.empty?

        "Dependency changes:\n#{bumps.map { |bump| "  #{bump}" }.join("\n")}"
      end

      def owners_text(files, owners)
        return "No CODEOWNERS file, so no owners are named." unless owners

        by_owner = files.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |file, grouped|
          owners.for(file["filename"]).each { |owner| grouped[owner] << file["filename"] }
        end
        return "CODEOWNERS names no owner for these files." if by_owner.empty?

        "Owners of the changed files, from CODEOWNERS:\n#{by_owner.map { |owner, paths| "  #{owner}: #{paths.join(', ')}" }.join("\n")}"
      end

      # A build log as lines a person reads, without colour codes, section markers or a progress bar's earlier states,
      # filtered as asked and cut to its last lines. Returns the lines kept and how many matched.
      def build_log_lines(raw, arguments)
        lines = raw.to_s.split(/\r?\n/).filter_map do |line|
          shown = line.gsub(ANSI, "").split("\r").map { |part| part.sub(SECTION_MARK, "") }.reject(&:blank?).last.to_s.rstrip
          shown unless shown.empty?
        end
        text, exclude = arguments["text"].to_s, arguments["exclude"].to_s
        pattern = log_pattern(arguments["regex"])
        matched = lines.select do |line|
          (text.empty? || line.include?(text)) && (exclude.empty? || !line.include?(exclude)) && (pattern.nil? || pattern.match?(line))
        end
        limit = (Integer(arguments["limit"].to_s, exception: false) || LOG_LINES).clamp(1, MAX_LOG_LINES)
        [ matched.last(limit), matched.size ]
      rescue Regexp::TimeoutError
        fail! "The regular expression took too long on this log. Give a simpler one, or text instead."
      end

      def log_pattern(regex)
        return nil if regex.blank?

        Regexp.new(regex.to_s, timeout: REGEX_TIMEOUT)
      rescue RegexpError => error
        fail! "regex is not a regular expression: #{error.message}"
      end

      def log_text(heading, kept, matched)
        return "#{heading}\nNo line matched." if kept.empty?

        shown = kept.size < matched ? "the last #{kept.size} of #{matched} lines" : "#{kept.size} lines"
        "#{heading}\nIts log, #{shown}:\n#{kept.join("\n")}"
      end

      def whole_number_argument(arguments, key, default, most)
        (Integer(arguments[key].to_s, exception: false) || default).clamp(1, most)
      end

      def numbered(lines, from, to)
        lines[(from - 1)..(to - 1)].each_with_index.map { |line, index| format("%4d  %s", from + index, line.chomp) }.join("\n")
      end
    end
  end
end
