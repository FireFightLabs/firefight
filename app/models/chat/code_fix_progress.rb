# What a coding agent writing a change has done so far, kept on its step so a reload or a second viewer sees the same.
# Lines name paths and commands, never what a file holds, and are redacted before they are kept.
class Chat::CodeFixProgress
  RESULT_PASSED = "passed"
  RESULT_FAILED = "failed"
  RESULTS = [ RESULT_PASSED, RESULT_FAILED ].freeze

  OUTCOME_OPENED = "opened"
  OUTCOME_PUSHED = "pushed"
  OUTCOME_FAILED = "failed"
  # It reached its spending limit and waits for the person to continue or stop it.
  OUTCOME_PAUSED = "paused"
  OUTCOMES = [ OUTCOME_OPENED, OUTCOME_PUSHED, OUTCOME_FAILED, OUTCOME_PAUSED ].freeze

  # Where the change goes, known before the agent starts: a new pull request, one already open, or a branch with none.
  TARGET_NEW_PULL_REQUEST = "new_pull_request"
  TARGET_PULL_REQUEST = "pull_request"
  TARGET_BRANCH = "branch"
  TARGETS = [ TARGET_NEW_PULL_REQUEST, TARGET_PULL_REQUEST, TARGET_BRANCH ].freeze

  # The newest lines are kept and the rest only counted, so a long run stays small.
  LINES_KEPT = 60
  LINE_LIMIT = 160
  CHANGED_KEPT = 100
  TESTS_KEPT = 20
  REASON_LIMIT = 300
  HEADLINE_LIMIT = 250
  WAITING = "Waiting for your answer"

  Line = Data.define(:text, :at, :result)
  Test = Data.define(:command, :passed)
  ChangedFile = Data.define(:path, :added, :removed)

  # question is the agent's latest question as CodeAgentQuestion#to_h, checks what ran on the change in the sandbox, and
  # review what Halon's review of it found, as the code review hands it back.
  # pause is the change's pause at its spending limit as CodeAgentSession::Pause#to_h.
  attr_reader :started_at, :lines, :total, :changed, :tests, :files, :finished_at, :outcome, :pull_request, :reason, :question, :checks, :review,
              :pause

  # A review kept before it said what it verified and left out reads as having said nothing of either.
  REVIEW_LISTS = { "verified" => [], "unreviewed" => [] }.freeze
  # A question kept before questions had options reads as one with none.
  QUESTION_CHOICES = { "options" => [], "recommended" => nil, "recommendedReason" => nil, "chosen" => nil, "timeoutOutcome" => nil,
                       "changedTo" => nil, "changedBy" => nil, "changedAt" => nil, "changedChosen" => nil, "updatedAt" => nil }.freeze

  # reason says what a check that could not run was missing.
  Check = Data.define(:name, :status, :reason)

  # pull_request is the open pull request a change is added to, linked while it runs.
  def self.start(at: Time.current, target: TARGET_NEW_PULL_REQUEST, pull_request: nil) = new(started_at: at, target: target, pull_request: pull_request)

  def self.from_h(hash)
    return nil if hash.blank?

    data = hash.to_h.stringify_keys
    new(
      started_at: parse_time(data["startedAt"]) || Time.current, live: data["live"] == true, total: data["total"].to_i,
      lines: Array(data["lines"]).map { |line| Line.new(text: line["text"].to_s, at: parse_time(line["at"]), result: line["result"]) },
      changed: Array(data["changed"]).map(&:to_s),
      tests: Array(data["tests"]).map { |test| Test.new(command: test["command"].to_s, passed: test["passed"] == true) },
      files: Array(data["files"]).map { |file| ChangedFile.new(path: file["path"].to_s, added: file["added"], removed: file["removed"]) },
      finished_at: parse_time(data["finishedAt"]), outcome: data["outcome"], pull_request: data["pullRequest"], reason: data["reason"],
      question: data["question"].presence && QUESTION_CHOICES.merge(data["question"].to_h), review: data["review"].presence && REVIEW_LISTS.merge(data["review"].to_h),
      checks: Array(data["checks"]).map { |check| Check.new(name: check["name"].to_s, status: check["status"].to_s, reason: check["reason"]) },
      pause: data["pause"].presence, target: data["target"].presence
    )
  end

  def self.from_json(text)
    from_h(JSON.parse(text.to_s))
  rescue JSON::ParserError
    nil
  end

  def self.parse_time(value) = value.present? ? Time.zone.parse(value.to_s) : nil

  def initialize(started_at:, live: false, total: 0, lines: [], changed: [], tests: [], files: [], finished_at: nil, outcome: nil,
                 pull_request: nil, reason: nil, question: nil, checks: [], review: nil, pause: nil, target: nil)
    @started_at = started_at
    @target = target
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
    @question = question
    @checks = checks
    @review = review
    @pause = pause
  end

  # A box from an older image runs the agent without saying what it does.
  def live? = @live

  def live! = (@live = true)

  # A change kept before it said where it goes is read from how it ended.
  def target
    return @target if @target
    return TARGET_NEW_PULL_REQUEST unless outcome == OUTCOME_PUSHED

    pull_request ? TARGET_PULL_REQUEST : TARGET_BRANCH
  end

  def finished? = finished_at.present?

  def add(text, result: nil, at: Time.current)
    shown = clean(text, LINE_LIMIT)
    return if shown.blank?

    @lines = [ *@lines, Line.new(text: shown, at: at, result: (result if RESULTS.include?(result))) ].last(LINES_KEPT)
    @total += 1
  end

  # The agent waited again for the answer to its question. Waits in a row are one line that says how long so far, since
  # the agent asks again every few seconds.
  def waited!(since, at: Time.current)
    so_far = since && at > since ? ", #{waited_words(at - since)}" : ""
    last = @lines.last
    return add("#{WAITING}#{so_far}", at: at) unless last&.text&.start_with?(WAITING)

    @lines = [ *@lines[0...-1], Line.new(text: "#{WAITING}#{so_far}", at: last.at, result: nil) ]
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

  def asked!(question) = (@question = question)

  # Waiting on a person, so the headline says so rather than the agent's last step.
  def waiting_for_answer? = question.present? && question["status"] == CodeAgentQuestion::STATUS_OPEN && !finished?

  # Why principal cannot answer the agent's open question, or nil. Looked up within the workspace, since the work is
  # read back from what a step kept.
  def question_blocked_reason(workspace_id, principal)
    return unless waiting_for_answer?

    question_record(workspace_id)&.answer_blocked_reason(principal)
  end

  # Why principal cannot change the answer to the agent's settled question, or nil when they can.
  def question_change_blocked_reason(workspace_id, principal)
    return unless question

    question_record(workspace_id)&.change_answer_blocked_reason(principal)
  end

  # The question as it stands now rather than as the step last reported it, since its answer can change after the
  # change's last report. Returns self.
  def with_current_question(workspace_id)
    current = question && question_record(workspace_id)
    @question = current.to_h if current
    self
  end

  # Why principal cannot continue or stop the change paused here, or nil.
  def pause_blocked_reason(workspace_id, principal)
    return unless pause

    pause_record(workspace_id)&.decide_blocked_reason(principal)
  end

  # The questions and pauses many steps' changes name, read in one query each rather than once a step, which each step's
  # question and pause answer from. Their sessions are read together, since a question and a pause often share one.
  def self.preload_records(works, workspace_id)
    works = works.compact
    questions = CodeAgentQuestion.where(id: works.filter_map { |work| work.question&.dig("id") }, workspace_id: workspace_id).order(:created_at).to_a
    pauses = CodeAgentSession::Pause.where(id: works.filter_map { |work| work.pause&.dig("id") }, workspace_id: workspace_id).order(:created_at).to_a
    # One read for the sessions of both, listed in the order their pauses were made, which is how the page's pause cards
    # read the same sessions. The two reads are then one statement the query cache answers once, rather than the same
    # rows in whatever order the database returned the questions.
    sessions = CodeAgentSession.where(id: pauses.map(&:session_id) | questions.map(&:code_agent_session_id)).index_by(&:id)
    questions.each { |question| question.association(:session).target = sessions[question.code_agent_session_id] }
    pauses.each { |pause| pause.association(:session).target = sessions[pause.session_id] }
    works.each { |work| work.records_read(workspace_id, questions.index_by { |row| row.id.to_s }, pauses.index_by { |row| row.id.to_s }) }
  end

  def records_read(workspace_id, questions, pauses)
    (@question_records ||= {})[workspace_id] = questions[question["id"].to_s] if question
    (@pause_records ||= {})[workspace_id] = pauses[pause["id"].to_s] if pause
  end

  # Only a check's name, how it went and what one that could not run was missing are kept, never what it printed, which
  # can quote the repository.
  def checked!(found)
    @checks = found.map { |check| Check.new(name: clean(check.name, LINE_LIMIT), status: check.status, reason: check.reason) }
    return if found.empty?

    not_run = found.count(&:could_not_run?)
    failed = found.size - not_run - found.count(&:passed?)
    ran = found.size - not_run
    words = failed.zero? ? "#{ran} #{'check'.pluralize(ran)} passed" : "#{failed} of #{ran} failed"
    add([ "Checked the change: #{words}", ("#{not_run} could not run here" if not_run.positive?) ].compact.join(", "),
        result: failed.zero? ? RESULT_PASSED : RESULT_FAILED)
  end

  def reviewed!(found) = (@review = found)

  # Stopped at its spending limit, waiting for the person to continue or stop it.
  def paused!(pause, at: Time.current)
    @pause = pause
    @outcome = OUTCOME_PAUSED
    @finished_at = at
  end

  # The person decided on the pause.
  def pause_moved!(pause) = (@pause = pause)

  def paused? = outcome == OUTCOME_PAUSED

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
    lead = finished? ? finished_words : (waiting_words || current&.text)
    [ lead, *counts ].compact.join(" · ").truncate(HEADLINE_LIMIT)
  end

  STAGE_PENDING = "pending".freeze
  STAGE_RUNNING = "running".freeze
  STAGE_DONE = "done".freeze
  STAGE_FAILED = "failed".freeze
  STAGES = [ STAGE_PENDING, STAGE_RUNNING, STAGE_DONE, STAGE_FAILED ].freeze
  # One part of the change a person follows while it runs, with a line on how it stands and the page it made, if any.
  Stage = Data.define(:key, :title, :status, :detail, :link)

  # The change as three parts, writing it, checking it and handing it over, for a checklist redrawn as it moves. Counts
  # only, never the files or commands, since it is read in a channel.
  def stages
    checked = checks.any? || tests.any?
    written = checked || finished?
    shown = [
      Stage.new(key: "write", title: "Write the change", status: stage_status(written, !written), detail: written_words, link: nil),
      Stage.new(key: "check", title: "Check the change", status: check_status(checked, written), detail: (checked_words if checked), link: nil),
      Stage.new(key: "hand_over", title: hand_over_title, status: hand_over_status(written), detail: (finished_words if WROTE.include?(outcome)),
                link: pull_request.presence)
    ]
    shown.map { |stage| stage.status == STAGE_FAILED && outcome == OUTCOME_FAILED ? stage.with(detail: finished_words) : stage }
  end

  # How far it got in counts alone, for a channel, where the latest thing it did would name files and commands.
  def counts_line
    lead = waiting_for_answer? ? "Waiting for an answer" : "Writing the change"
    "#{lead}: #{counts.join(', ')} so far"
  end

  # The same for a chat's thread, which also says how it ended once it has.
  def thread_line
    finished? ? [ finished_words, *counts ].join(" · ").truncate(HEADLINE_LIMIT) : counts_line
  end

  def counts
    counts = [ "#{total} #{'step'.pluralize(total)}" ]
    counts << "#{changed.size} #{'file'.pluralize(changed.size)} changed" if changed.any?
    counts << tests_words if tests.any?
    counts
  end

  # Changes only when there is something new to show.
  def signature = [ total, changed.size, tests.size, live?, outcome, question&.values_at("id", "status")&.join("/"), review.present? ].join(":")

  # Kept and sent in the shape the page reads, AgentChatMessageSerializer::PROGRESS_TYPE.
  def to_h
    {
      "startedAt" => started_at&.utc&.iso8601, "live" => live?, "total" => total,
      "lines" => lines.map { |line| { "text" => line.text, "at" => line.at&.utc&.iso8601, "result" => line.result } },
      "changed" => changed, "tests" => tests.map { |test| { "command" => test.command, "passed" => test.passed } },
      "files" => files.map { |file| { "path" => file.path, "added" => file.added, "removed" => file.removed } },
      "finishedAt" => finished_at&.utc&.iso8601, "outcome" => outcome, "pullRequest" => pull_request, "reason" => reason,
      "question" => question, "checks" => checks.map { |check| { "name" => check.name, "status" => check.status, "reason" => check.reason } }, "review" => review,
      "pause" => pause, "target" => @target
    }
  end

  def to_json(*) = to_h.to_json(*)

  private

  WROTE = [ OUTCOME_OPENED, OUTCOME_PUSHED ].freeze

  def stopped? = [ OUTCOME_FAILED, OUTCOME_PAUSED ].include?(outcome)

  # A part done, the one under way, or the one a stop ended on.
  def stage_status(done, current)
    return STAGE_DONE if done
    return (outcome == OUTCOME_FAILED ? STAGE_FAILED : STAGE_RUNNING) if current

    STAGE_PENDING
  end

  def check_status(checked, written)
    return (checks_failed? ? STAGE_FAILED : STAGE_DONE) if checked
    return STAGE_FAILED if written && outcome == OUTCOME_FAILED

    STAGE_PENDING
  end

  def checks_failed? = checks.any? ? checks.any? { |check| check.status == Integrations::CodeChecks::FAILED } : tests.last&.passed == false

  def hand_over_status(written)
    return STAGE_DONE if WROTE.include?(outcome)
    return STAGE_RUNNING if written && !stopped?

    STAGE_PENDING
  end

  HAND_OVER_TITLES = {
    TARGET_NEW_PULL_REQUEST => "Open a pull request", TARGET_PULL_REQUEST => "Push to the pull request", TARGET_BRANCH => "Push to the branch"
  }.freeze

  def hand_over_title = HAND_OVER_TITLES.fetch(target)

  def written_words
    return waiting_words if waiting_for_answer?
    return "#{changed.size} #{'file'.pluralize(changed.size)} changed" if changed.any?

    "#{total} #{'step'.pluralize(total)} so far" if total.positive?
  end

  def checked_words = checks.any? ? lines.reverse.find { |line| line.text.start_with?("Checked the change") }&.text : tests_words

  def waited_words(seconds)
    seconds < 60 ? "#{seconds.round}s" : "#{(seconds / 60).floor}m"
  end

  def waiting_words = ("Waiting for an answer: #{question['text']}" if waiting_for_answer?)

  def tests_words
    last = tests.last
    last.passed ? "tests passed" : "tests failed"
  end

  def finished_words
    return "Opened the pull request" if outcome == OUTCOME_OPENED
    return pull_request ? "Added to the pull request" : "Pushed to the branch" if outcome == OUTCOME_PUSHED
    return "Paused at its spending limit" if outcome == OUTCOME_PAUSED

    "Stopped: #{reason}"
  end

  def wrote!(outcome, files, pull_request, at)
    @files = files.map { |path, (added, removed)| ChangedFile.new(path: clean(path, LINE_LIMIT), added: added, removed: removed) }
    @pull_request = pull_request
    @outcome = outcome
    @finished_at = at
  end

  def clean(text, limit) = Chat::SecretFree.redacted(text.to_s.squish).truncate(limit)

  def question_record(workspace_id)
    @question_records ||= {}
    @question_records.fetch(workspace_id) { @question_records[workspace_id] = CodeAgentQuestion.find_by(id: question["id"], workspace_id: workspace_id) }
  end

  def pause_record(workspace_id)
    @pause_records ||= {}
    @pause_records.fetch(workspace_id) { @pause_records[workspace_id] = CodeAgentSession::Pause.find_by(id: pause["id"], workspace_id: workspace_id) }
  end
end
