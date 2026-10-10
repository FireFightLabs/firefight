# Two bench runs side by side, scenario by scenario, and whether the newer one dropped. Only scenarios both runs scored
# are counted in either total, so adding or removing a scenario never moves the comparison.
class Conversation::BenchComparison
  # Two replays of the same chat on the same model differ a little, so a drop smaller than this is noise.
  TOLERANCE = 0.05

  Row = Data.define(:scenario, :title, :base, :head) do
    def delta
      (head.total - base.total).round(3) if both?
    end

    def both? = base&.total.present? && head&.total.present?
  end

  # A run as it is written to a file, so CI can compare with a run another database recorded.
  def self.export(run)
    {
      "kind" => run.kind, "model" => run.model, "provider" => run.provider, "prompt_version" => run.prompt_version, "label" => run.label,
      "scenarios" => run.results.order(:scenario).to_h do |result|
        [ result.scenario, { "title" => result.title, "status" => result.status, **result.score.to_h.stringify_keys, "total" => result.total,
                             "spent_micros" => result.spent_micros, "notes" => result.notes } ]
      end
    }
  end

  def self.from_runs(base, head) = from_exports(export(base), export(head))

  def self.from_exports(base, head)
    new(base: scored(base), head: scored(head), comparable: [ base["model"], base["provider"] ] == [ head["model"], head["provider"] ])
  end

  # Each scored scenario's score and title, from an export.
  def self.scored(export)
    export.fetch("scenarios").filter_map do |key, entry|
      next unless entry["status"] == Conversation::BenchResult::STATUS_SCORED

      [ key, [ entry["title"], Conversation::BenchScore.new(**Conversation::BenchScore.dimensions.index_with { |dimension| entry[dimension.to_s] }) ] ]
    end.to_h
  end

  # comparable is whether both runs used the same model. A drop between two models says how they differ, not that Halon
  # got worse, so it never fails a change.
  def initialize(base:, head:, comparable: true)
    @base = base
    @head = head
    @comparable = comparable
  end

  def comparable? = @comparable

  def rows
    (@base.keys | @head.keys).sort.map do |key|
      Row.new(scenario: key, title: (@head[key] || @base[key]).first, base: @base[key]&.last, head: @head[key]&.last)
    end
  end

  def shared = rows.select(&:both?)

  def base_total = mean(shared.map { |row| row.base.total })

  def head_total = mean(shared.map { |row| row.head.total })

  # The mean of one dimension over the shared scenarios, for one side.
  def dimension(side, name) = mean(shared.filter_map { |row| row.public_send(side).public_send(name) })

  def dropped? = shared.any? && head_total < base_total - TOLERANCE

  # What fails a change: a drop larger than the noise between two runs on the same model.
  def failed? = comparable? && dropped?

  # Scenarios that scored lower by more than the noise, worst first, since those are where to read the replay.
  def worse = shared.select { |row| row.delta < -TOLERANCE }.sort_by(&:delta)

  private

  def mean(values) = values.empty? ? nil : (values.sum / values.size).round(3)
end
