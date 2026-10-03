# One week of answers on the Performance page, by what the team said of them.
class HalonPerformanceWeekSerializer < BaseSerializer
  object_as :week

  type :string
  def starts_on = week.starts_on.iso8601

  type :number
  def confirmed = week.confirmed

  type :number
  def partial = week.partial

  type :number
  def wrong = week.wrong

  type :number
  def not_rated = week.not_rated
end
