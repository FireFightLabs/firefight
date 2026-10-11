# Two bench runs side by side, scenario by scenario, and whether the newer one dropped. Each side of a scenario is the
# mean of its repeats (Conversation::BenchTally). Only scenarios both runs scored are counted in either total, so adding
# or removing a scenario never moves the comparison.
class Conversation::BenchComparison
  # The least a drop must be to count. Two replays of the same chat on the same model differ a little, so a drop no
  # larger than this, or than the spread either run saw between its own repeats, is noise.
  TOLERANCE = 0.05

  Row = Data.define(:scenario, :title, :base, :head) do
    def delta
      (head.total - base.total).round(3) if both?
    end

    def both? = base&.total.present? && head&.total.present?

    # What this scenario's own repeats say a drop has to beat.
    def noise = [ TOLERANCE, base&.spread, head&.spread ].compact.max
  end

  # A run as it is written to a file, so CI can compare with a run another database recorded.
  def self.export(run)
    tallies = Conversation::BenchTally.of_run(run)
    {
      "kind" => run.kind, "model" => run.model, "provider" => run.provider, "prompt_version" => run.prompt_version, "label" => run.label,
      "repeats" => run.repeats, "spread" => Conversation::BenchTally.spread(tallies),
      "agreeing" => Conversation::BenchTally.agreeing(tallies), "repeated" => Conversation::BenchTally.repeated(tallies),
      "scenarios" => tallies.to_h { |tally| [ tally.scenario, tally.to_export ] }
    }
  end

  def self.from_runs(base, head) = from_exports(export(base), export(head))

  def self.from_exports(base, head)
    new(base: scored(base), head: scored(head), comparable: [ base["model"], base["provider"] ] == [ head["model"], head["provider"] ],
        spreads: [ base["spread"], head["spread"] ])
  end

  # Each scenario some replay of scored, from an export.
  def self.scored(export)
    export.fetch("scenarios").to_h { |key, entry| [ key, Conversation::BenchTally.from_export(key, entry) ] }.select { |_key, tally| tally.scored? }
  end

  # comparable is whether both runs used the same model. A drop between two models says how they differ, not that Halon
  # got worse, so it never fails a change. spreads are how far apart each run's own passes lay.
  def initialize(base:, head:, comparable: true, spreads: [])
    @base = base
    @head = head
    @comparable = comparable
    @spreads = spreads
  end

  def comparable? = @comparable

  def rows
    (@base.keys | @head.keys).sort.map do |key|
      Row.new(scenario: key, title: (@head[key] || @base[key]).title, base: @base[key], head: @head[key])
    end
  end

  def shared = rows.select(&:both?)

  def base_total = mean(shared.map { |row| row.base.total })

  def head_total = mean(shared.map { |row| row.head.total })

  # The mean of one score over the shared scenarios, for one side. quality is the mean of its three.
  def dimension(side, name) = mean(shared.filter_map { |row| row.public_send(side).score.public_send(name) })

  # What the totals have to drop by to count, the tolerance or the spread either run saw between its own passes.
  def noise = [ TOLERANCE, *@spreads.compact ].max

  def dropped? = shared.any? && head_total < base_total - noise

  # What fails a change: a drop larger than the noise between two runs on the same model.
  def failed? = comparable? && dropped?

  # Scenarios that scored lower by more than their own noise, worst first, since those are where to read the replay.
  def worse = shared.select { |row| row.delta < -row.noise }.sort_by(&:delta)

  private

  def mean(values) = values.empty? ? nil : (values.sum / values.size).round(3)
end
