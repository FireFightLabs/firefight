# What a bench replay is scored on, each from 0 to 1. Quality is the mean of right (the answer and what it did were
# right), moved forward and asked when needed. Cost is apart, and so is citing the evidence, so a right answer that
# forgot a link is still right. Right is nil for a real chat replayed with nothing said about its right outcome, and
# cited is nil when the scenario names no evidence. The total, kept so runs before quality was apart still compare, is
# the mean of quality's three and cost.
class Conversation::BenchScore < Data.define(:right, :moved_forward, :asked_when_needed, :cost, :cited)
  def initialize(right:, moved_forward:, asked_when_needed:, cost:, cited: nil) = super

  def self.dimensions = members

  QUALITY = %i[right moved_forward asked_when_needed].freeze
  TOTAL = [ *QUALITY, :cost ].freeze

  def quality = mean(QUALITY)

  def total = mean(TOTAL)

  # Each score's mean over several replays of one scenario, leaving out a score none of them has.
  def self.mean(scores)
    new(**dimensions.index_with do |name|
      given = scores.filter_map { |score| score.public_send(name) }
      given.empty? ? nil : (given.sum / given.size).round(3)
    end)
  end

  # What a replay reached against what its scenario expects, from the transcript, the judge's verdict and what it spent.
  # A scenario's evidence is texts a right answer cites, usually the links a tool returned. Its calls are tools taking
  # the next step means calling, such as start_watch after starting a release.
  def self.of(transcript:, verdict:, expect:, spent_micros:)
    new(
      right: right(verdict, transcript, expect),
      moved_forward: moved_forward(verdict, transcript, expect),
      asked_when_needed: asked_when_needed(verdict, transcript),
      cost: cost(spent_micros, expect.reference_cents),
      cited: cited(transcript, expect)
    )
  end

  OUTCOME_SCORES = { FirefightAi::Schemas::ReplayVerdict::REACHED => 1.0, FirefightAi::Schemas::ReplayVerdict::PARTLY => 0.5 }.freeze
  FORWARD_SCORES = { FirefightAi::Schemas::ReplayVerdict::YES => 1.0, FirefightAi::Schemas::ReplayVerdict::PARTLY => 0.5 }.freeze

  # An outcome nobody wrote down cannot be right or wrong. A call the scenario says a right run never makes, such as a
  # rollback of a deploy that did not cause it, makes the run wrong whatever the answer says.
  def self.right(verdict, transcript, expect)
    return nil if expect.outcome.blank?
    return 0.0 if forbidden(transcript, expect).any?

    OUTCOME_SCORES.fetch(verdict.outcome, 0.0)
  end

  # Whether a reply cites the scenario's evidence, nil when it names none.
  def self.cited(transcript, expect)
    return nil if expect.outcome.blank? || expect.evidence.empty?

    transcript.cites_any?(expect.evidence) ? 1.0 : 0.0
  end

  def self.forbidden(transcript, expect) = expect.never_calls.select { |name| transcript.called?(name) }

  def self.moved_forward(verdict, transcript, expect)
    parts = [ FORWARD_SCORES.fetch(verdict.moved_forward, 0.0) ]
    parts << (expect.calls.count { |name| transcript.called?(name) }.to_f / expect.calls.size) if expect.calls.any?
    parts << (forbidden(transcript, expect).empty? ? 1.0 : 0.0) if expect.never_calls.any?
    (parts.sum / parts.size).round(3)
  end

  # Every time it stopped for the person counts, a confirmation or a question. A confirmation for a call that only
  # reads, or a question it could have answered itself, was not needed.
  def self.asked_when_needed(verdict, transcript)
    asks = transcript.confirmations.size + verdict.questions
    return 1.0 if asks.zero?

    unneeded = transcript.unneeded_confirmations.size + verdict.unneeded_questions
    (1.0 - (unneeded.to_f / asks)).clamp(0.0, 1.0).round(3)
  end

  # What took marks away, in plain sentences naming tools but never what a call was given, since a real chat's
  # arguments are the customer's.
  def self.notes(transcript:, verdict:, expect:)
    [
      *transcript.unneeded_confirmations.map { |call| "Asked the person to confirm #{call.name}, a call that only read." },
      ("Asked #{verdict.unneeded_questions} #{verdict.unneeded_questions == 1 ? 'question' : 'questions'} it could have answered itself." if verdict.unneeded_questions.positive?),
      *expect.calls.reject { |name| transcript.called?(name) }.map { |name| "Never called #{name}." },
      *forbidden(transcript, expect).map { |name| "Called #{name}, which this scenario should never reach, so it was not right." },
      ("Cited none of the evidence a right answer links to." if cited(transcript, expect)&.zero?),
      unplaced(transcript.unplaced_charts.size),
      ("#{transcript.not_recorded} #{transcript.not_recorded == 1 ? 'call was' : 'calls were'} not in the record, so nothing answered them." if transcript.not_recorded.positive?)
    ].compact
  end

  def self.unplaced(count)
    return if count.zero?

    "Left #{count} #{count == 1 ? 'chart' : 'charts'} unplaced, so #{count == 1 ? 'it follows' : 'they follow'} the answer rather than sitting beside what #{count == 1 ? 'it shows' : 'they show'}."
  end
  private_class_method :unplaced

  # How many times the reference spend costs the whole score. On a log scale, so a model ten times the reference is
  # worth half and a hundred times nothing, which tells a cheap model from a dear one without one dear scenario
  # sinking the total.
  COST_SPREAD = 100.0

  # At or under the scenario's reference spend is full marks.
  def self.cost(spent_micros, reference_cents)
    spent_cents = spent_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f
    return 1.0 if spent_cents <= reference_cents

    (1.0 - (Math.log10(spent_cents / reference_cents) / Math.log10(COST_SPREAD))).clamp(0.0, 1.0).round(3)
  end

  private

  def mean(names)
    given = to_h.slice(*names).values.compact
    given.empty? ? nil : (given.sum / given.size).round(3)
  end
end
