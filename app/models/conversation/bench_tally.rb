# One scenario's replays in a bench run taken together: the mean of each score over those that scored, and how far
# apart their totals lay. A replay is a Conversation::BenchResult, or one read back from a file a run was written to
# (Conversation::BenchComparison.export), both answering attempt, status, score, spent_micros and notes.
class Conversation::BenchTally
  # A replay read back from a written run.
  Replay = Data.define(:attempt, :status, :score, :spent_micros, :notes)

  attr_reader :scenario, :title, :replays

  def initialize(scenario:, title:, replays:)
    @scenario = scenario
    @title = title
    @replays = replays.sort_by(&:attempt)
  end

  # Each scenario of a run, in order, from its results.
  def self.of_run(run) = of_results(run.results.to_a)

  def self.of_results(results)
    results.group_by(&:scenario).sort.map { |scenario, replays| new(scenario: scenario, title: replays.first.title, replays: replays) }
  end

  # A scenario as a written run holds it. A run written before repeats holds one replay, its scores at the top.
  def self.from_export(scenario, entry)
    written = entry["replays"].presence || [ entry.merge("attempt" => 1) ]
    replays = written.map do |replay|
      Replay.new(attempt: replay["attempt"].to_i, status: replay["status"], spent_micros: replay["spent_micros"].to_i, notes: Array(replay["notes"]),
                 score: Conversation::BenchScore.new(**Conversation::BenchScore.dimensions.index_with { |name| replay[name.to_s] }))
    end
    new(scenario: scenario, title: entry["title"], replays: replays)
  end

  # How far apart a run's whole passes lay: the mean total of each attempt over the scenarios every attempt scored,
  # highest less lowest. Nil with fewer than two attempts to set side by side.
  def self.spread(tallies)
    attempts = tallies.flat_map { |tally| tally.scored.map(&:attempt) }.uniq
    common = tallies.select { |tally| attempts.all? { |attempt| tally.scored.any? { |replay| replay.attempt == attempt } } }
    return nil if attempts.size < 2 || common.empty?

    means = attempts.map { |attempt| common.sum { |tally| tally.scored.find { |replay| replay.attempt == attempt }.score.total } / common.size }
    (means.max - means.min).round(3)
  end

  # The scenarios whose repeats agree, of those replayed more than once.
  def self.agreeing(tallies) = tallies.count(&:agrees?)

  def self.repeated(tallies) = tallies.count { |tally| tally.scored.size > 1 }

  def scored = replays.select { |replay| replay.status == Conversation::BenchResult::STATUS_SCORED }

  def status
    return Conversation::BenchResult::STATUS_SCORED if scored.any?
    return Conversation::BenchResult::STATUS_PENDING if replays.any? { |replay| replay.status == Conversation::BenchResult::STATUS_PENDING }

    Conversation::BenchResult::STATUS_ERRORED
  end

  def scored? = scored.any?

  # The mean of each score over the replays that scored, nil when none did.
  def score = scored? ? Conversation::BenchScore.mean(scored.map(&:score)) : nil

  def total = score&.total

  def quality = score&.quality

  # Highest total less lowest, nil with fewer than two replays scored.
  def spread
    totals = scored.filter_map { |replay| replay.score.total }
    totals.size < 2 ? nil : (totals.max - totals.min).round(3)
  end

  def agrees? = !spread.nil? && spread <= Conversation::BenchRun::AGREEMENT

  def spent_micros = replays.sum(&:spent_micros)

  def notes = scored.flat_map(&:notes).uniq

  def to_export
    {
      "title" => title, "status" => status, **(score&.to_h || {}).stringify_keys, "total" => total, "quality" => quality, "spread" => spread,
      "spent_micros" => spent_micros, "notes" => notes,
      "replays" => replays.map do |replay|
        { "attempt" => replay.attempt, "status" => replay.status, **replay.score.to_h.stringify_keys, "total" => replay.score.total,
          "quality" => replay.score.quality, "spent_micros" => replay.spent_micros, "notes" => replay.notes }
      end
    }
  end
end
