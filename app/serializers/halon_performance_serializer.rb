# How Halon has done for the workspace over the chosen window, for the Performance page.
class HalonPerformanceSerializer < BaseSerializer
  object_as :performance

  type :number
  def days = performance.days

  type :number
  def runs = performance.runs_count

  type :number
  def ended = performance.ended_count

  type :number
  def answered = performance.answered_count

  type :number, optional: true
  def median_seconds = performance.median_seconds

  type :number
  def confirmed = performance.verdicts[Investigation::Finding::OUTCOME_CONFIRMED]

  type :number
  def partial = performance.verdicts[Investigation::Finding::OUTCOME_PARTIAL]

  type :number
  def wrong = performance.verdicts[Investigation::Finding::OUTCOME_WRONG]

  type :number
  def not_rated = performance.verdicts[Investigation::Performance::NOT_RATED]

  type :number
  def rated = performance.rated_count

  type :number
  def fixes_proposed = performance.fixes.proposed

  type :number
  def fixes_applied = performance.fixes.applied

  type :number
  def fixes_undone = performance.fixes.undone

  type :number
  def fixes_cancelled = performance.fixes.cancelled

  has_many :weeks, serializer: HalonPerformanceWeekSerializer
  has_many :mistakes, serializer: HalonMistakeSerializer
end
