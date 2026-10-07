# What a coding agent writing a change has done so far, kept on its step so a reload or a second viewer sees the same.
# Lines name paths and commands, never what a file holds, and are redacted before they are kept.
class Chat::CodeFixProgress
  RESULT_PASSED = "passed"
  RESULT_FAILED = "failed"
  RESULTS = [ RESULT_PASSED, RESULT_FAILED ].freeze

  OUTCOME_OPENED = "opened"
  OUTCOME_PUSHED = "pushed"
  OUTCOME_FAILED = "failed"
  OUTCOMES = [ OUTCOME_OPENED, OUTCOME_PUSHED, OUTCOME_FAILED ].freeze

  # The newest lines are kept and the rest only counted, so a long run stays small.
  LINES_KEPT = 60
  LINE_LIMIT = 160
  CHANGED_KEPT = 100
  TESTS_KEPT = 20
  REASON_LIMIT = 300
  HEADLINE_LIMIT = 250

  Line = Data.define(:text, :at, :result)
  Test = Data.define(:command, :passed)
  ChangedFile = Data.define(:path, :added, :removed)

  attr_reader :started_at, :lines, :total, :changed, :tests, :files, :finished_at, :outcome, :pull_request, :reason

  def self.start(at: Time.current) = new(started_at: at)

  def self.from_h(hash)
    return nil if hash.blank?

    data = hash.to_h.stringify_keys
    new(
      started_at: parse_time(data["startedAt"]) || Time.current, live: data["live"] == true, total: data["total"].to_i,
      lines: Array(data["lines"]).map { |line| Line.new(text: line["text"].to_s, at: parse_time(line["at"]), result: line["result"]) },
      changed: Array(data["changed"]).map(&:to_s),
      tests: Array(data["tests"]).map { |test| Test.new(command: test["command"].to_s, passed: test["passed"] == true) },
      files: Array(data["files"]).map { |file| ChangedFile.new(path: file["path"].to_s, added: file["added"], removed: file["removed"]) },
      finished_at: parse_time(data["finishedAt"]), outcome: data["outcome"], pull_request: data["pullRequest"], reason: data["reason"]
    )
  end

  def self.from_json(text)
    from_h(JSON.parse(text.to_s))
  rescue JSON::ParserError
    nil
  end

  def self.parse_time(value) = value.present? ? Time.zone.parse(value.to_s) : nil

  def initialize(started_at:, live: false, total: 0, lines: [], changed: [], tests: [], files: [], finished_at: nil, outcome: nil,
                 pull_request: nil, reason: nil)
    @started_at = started_at
    @live = live
    @total = total
    @lines = lines
    @changed = changed
    @tests = tests
    @files = files
    @finished_at = finished_at
    @outcome = outcome
    @pull_request = pull_request
    @reason = reason
  end

  # A box from an older image runs the agent without saying what it does.
  def live? = @live

  def live! = (@live = true)

  def finished? = finished_at.present?

  def add(text, result: nil, at: Time.current)
    shown = clean(text, LINE_LIMIT)
    return if shown.blank?

    @lines = [ *@lines, Line.new(text: shown, at: at, result: (result if RESULTS.include?(result))) ].last(LINES_KEPT)
    @total += 1
  end

  def changed!(path)
    shown = clean(path, LINE_LIMIT)
    @changed = [ *@changed, shown ].uniq.last(CHANGED_KEPT) if shown.present?
  end

  def tested!(command, passed:)
    @tests = [ *@tests, Test.new(command: clean(command, LINE_LIMIT), passed: passed) ].last(TESTS_KEPT)
  end

  # Lines added and removed are nil for a binary file.
  def opened!(files:, pull_request:, at: Time.current) = wrote!(OUTCOME_OPENED, files, pull_request, at)

  # Added as a commit to a branch that already existed. The pull request is nil when the branch has none open.
  def pushed!(files:, pull_request:, at: Time.current) = wrote!(OUTCOME_PUSHED, files, pull_request, at)

  def failed!(reason, at: Time.current)
    @reason = clean(reason.to_s.lines.first, REASON_LIMIT)
    @outcome = OUTCOME_FAILED
    @finished_at = at
  end

  def current = lines.last

  # The latest thing it did and how far it got, in one line.
  def headline
    counts = [ "#{total} #{'step'.pluralize(total)}" ]
    counts << "#{changed.size} #{'file'.pluralize(changed.size)} changed" if changed.any?
    counts << tests_words if tests.any?
    lead = finished? ? finished_words : current&.text
    [ lead, *counts ].compact.join(" · ").truncate(HEADLINE_LIMIT)
  end

  # Changes only when there is something new to show.
  def signature = [ total, changed.size, tests.size, live?, outcome ].join(":")

  # Kept and sent in the shape the page reads, AgentChatMessageSerializer::PROGRESS_TYPE.
  def to_h
    {
      "startedAt" => started_at&.utc&.iso8601, "live" => live?, "total" => total,
      "lines" => lines.map { |line| { "text" => line.text, "at" => line.at&.utc&.iso8601, "result" => line.result } },
      "changed" => changed, "tests" => tests.map { |test| { "command" => test.command, "passed" => test.passed } },
      "files" => files.map { |file| { "path" => file.path, "added" => file.added, "removed" => file.removed } },
      "finishedAt" => finished_at&.utc&.iso8601, "outcome" => outcome, "pullRequest" => pull_request, "reason" => reason
    }
  end

  def to_json(*) = to_h.to_json(*)

  private

  def tests_words
    last = tests.last
    last.passed ? "tests passed" : "tests failed"
  end

  def finished_words
    return "Opened the pull request" if outcome == OUTCOME_OPENED
    return pull_request ? "Added to the pull request" : "Pushed to the branch" if outcome == OUTCOME_PUSHED

    "Stopped: #{reason}"
  end

  def wrote!(outcome, files, pull_request, at)
    @files = files.map { |path, (added, removed)| ChangedFile.new(path: clean(path, LINE_LIMIT), added: added, removed: removed) }
    @pull_request = pull_request
    @outcome = outcome
    @finished_at = at
  end

  def clean(text, limit) = Chat::SecretFree.redacted(text.to_s.squish).truncate(limit)
end
