# The check one reported finding gets before it is written: a verifier on a chat of its own, reading the pull request's
# head with the same tools as the review, that keeps or drops it and says what it showed of each earlier finding. A kept
# finding is written at once with its corrections and announced, then each earlier one it touched is confirmed,
# strengthened or withdrawn. What it spends comes out of the review's budget. Answers what the reviewer is told.
class PullRequestReview::Verification
  # The steps of a check kept on the finding as how it was checked, each cut to this.
  STEP_LIMIT = 200
  STEPS_KEPT = 12
  # The arguments a step is named by, the first one present, such as the command a shell ran.
  NAMED_BY = %w[command symbol pattern query sql path name identifier repo].freeze
  CORRECTABLE = %w[category severity effort serious line claim why failure_chain].freeze
  STRENGTHENABLE = %w[category severity effort serious why].freeze

  def initialize(runner, proposal)
    @runner = runner
    @proposal = proposal
    @steps = []
  end

  def run
    review = @runner.review
    duplicate = review.findings.find_by(fingerprint: fingerprint(@proposal.attributes))
    return "Not written again. It is finding #{duplicate.position}, which was withdrawn: #{duplicate.withdrawn_reason}" if duplicate&.withdrawn?
    return "Not written again. It is finding #{duplicate.position} already." if duplicate

    check = review.checks.create!(claim: @proposal.claim, path: @proposal.path)
    left = @runner.purse.left(review.max_spend_cents)
    if left <= 0
      check.update!(reason: "The review's spending limit ran out before this could be checked.")
      return "Not written. The review's spending limit ran out before it could be checked."
    end

    settle = PullRequestReview::SettleFinding.new(earlier_findings.map(&:position))
    outcome = verify(check, settle, left)
    return unsettled(check, outcome) unless settle.settled?

    apply(check, settle.settled, outcome)
  end

  private

  def verify(check, settle, left_micros)
    chat = Chat.open!(owner: check, workspace: @runner.review.workspace, model_choice: @runner.choice)
    tools, deferred = PullRequestReview::Agent.new(@runner.review, chat: chat).tools(@runner.choice)
    counted = 0
    @runner.verifier.run(
      chat: chat, tools: tools + [ settle ], deferred_tools: deferred, finding: @proposal.text, earlier: earlier_text, context: @runner.check_context(@proposal.path),
      max_spend_cents: (left_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).ceil, settled: -> { settle.settled? }, canceled: @runner.canceled,
      on_step: ->(step) { @steps << step if step.status == FirefightAi::AgentLoop::STEP_RUNNING && step.tool != PullRequestReview::SettleFinding::NAME }
    ) do |turn|
      @runner.purse.add(turn.spent_micros - counted)
      counted = turn.spent_micros
    end
  end

  def unsettled(check, outcome)
    check.update!(reason: "The check ended before it settled the finding (#{outcome.status.to_s.humanize.downcase}).", spent_micros: outcome.spent_micros)
    "Not written. Its check ended before it could settle it, so it was not verified."
  end

  def apply(check, settled, outcome)
    review = @runner.review
    unless settled.keep?
      changed = PullRequestReview::Finding.transaction { earlier!(settled.earlier, by: nil) }
      check.settled!(PullRequestReview::Check::VERDICT_DROPPED, reason: settled.reason, spent_micros: outcome.spent_micros)
      return [ "Not written. The check dropped it: #{settled.reason}", *changed ].join(" ")
    end

    finding, changed = PullRequestReview::Finding.transaction do
      # The review's row is held until this commits, so two checks writing at once take positions one after the other.
      PullRequestReview.where(id: review.id).lock.pick(:id)
      written = review.findings.create!(finding_attributes(settled))
      [ written, earlier!(settled.earlier, by: written) ]
    end
    check.settled!(PullRequestReview::Check::VERDICT_KEPT, reason: settled.reason, finding: finding, spent_micros: outcome.spent_micros)
    dropped = " Some evidence was left out: #{@proposal.dropped.join(' ')}" if @proposal.dropped.any?
    [ "Written as finding #{finding.position}#{' with the check\'s corrections' if settled.corrections.any?}.#{dropped}", *changed ].join(" ")
  # Only the same problem written meanwhile by another worker is a duplicate. Any other unique index is a fault.
  rescue ActiveRecord::RecordNotUnique => error
    raise unless error.message.include?(PullRequestReview::Finding::FINGERPRINT_INDEX)

    check.settled!(PullRequestReview::Check::VERDICT_DROPPED, reason: "The same finding was written already.", spent_micros: outcome.spent_micros)
    "Not written again. The same finding was written already."
  end

  def finding_attributes(settled)
    corrected = @proposal.attributes.merge(settled.corrections.slice(*CORRECTABLE).symbolize_keys.compact_blank) do |key, given, correction|
      valid_correction?(key, correction) ? correction : given
    end
    corrected[:serious] = settled.corrections["serious"] if [ true, false ].include?(settled.corrections["serious"])
    corrected[:failure_chain] = Array(corrected[:failure_chain]).map { |step| step.to_s.squish }.compact_blank
    corrected.merge(
      position: @runner.review.next_position, fingerprint: fingerprint(corrected), outside_diff: @runner.outside_diff?(corrected[:path], corrected[:line]),
      checks: @steps.first(STEPS_KEPT).map { |step| named(step) }
    )
  end

  def valid_correction?(key, value)
    case key
    when :category then PullRequestReview::Finding::CATEGORIES.include?(value)
    when :severity then PullRequestReview::Finding::SEVERITIES.include?(value)
    when :effort then PullRequestReview::Finding::EFFORTS.include?(value)
    when :line then value.is_a?(Integer) && value.positive?
    when :failure_chain then value.is_a?(Array) && value.any?
    else value.is_a?(String)
    end
  end

  # What the check showed of each earlier finding it named, applied, said as the reviewer reads it. A finding another
  # worker withdrew or fixed meanwhile is left as it is and goes unsaid. They are written in the findings' order, so two
  # checks touching the same findings lock them in the same order and never wait on each other.
  def earlier!(outcomes, by:)
    found = earlier_findings.index_by(&:position)
    outcomes.sort_by(&:number).filter_map do |outcome|
      finding = found[outcome.number]
      next unless finding

      case outcome.outcome
      when PullRequestReview::SettleFinding::CONFIRM
        "It confirmed finding #{finding.position}." if finding.confirmed!(outcome.note, by: by)
      when PullRequestReview::SettleFinding::STRENGTHEN
        changes = outcome.changes.slice(*STRENGTHENABLE).select { |key, value| valid_correction?(key.to_sym, value) || key == "serious" && [ true, false ].include?(value) }
        "It strengthened finding #{finding.position}." if finding.strengthened!(outcome.note, by: by, **changes.symbolize_keys)
      when PullRequestReview::SettleFinding::WITHDRAW
        "It withdrew finding #{finding.position}: #{outcome.note}" if finding.withdraw!(outcome.note, by: by)
      end
    end
  end

  def earlier_findings = @earlier_findings ||= @runner.review.findings.still_open.to_a

  def earlier_text
    earlier_findings.map do |finding|
      "#{finding.position}. #{finding.header}#{' | serious' if finding.serious}, #{finding.path}#{":#{finding.line}" if finding.line}\n" \
        "Claim: #{finding.claim}\nWhy: #{finding.why}\nChain: #{finding.failure_chain.join(' Then ')}"
    end.join("\n\n")
  end

  def fingerprint(attributes) = PullRequestReview::Finding.fingerprint_for(path: attributes[:path], category: attributes[:category], claim: attributes[:claim])

  def named(step)
    arguments = step.arguments.to_h.stringify_keys
    value = NAMED_BY.lazy.filter_map { |key| arguments[key].presence }.first
    [ step.tool, value&.to_s&.squish ].compact.join(": ").truncate(STEP_LIMIT)
  end
end
