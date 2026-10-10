# One freeze window a handbook page sets, as its form edits it and as the page reads it out.
class HandbookFreezeWindowSerializer < BaseSerializer
  object_as :rule

  type :string
  def name = rule.name

  type "'weekly' | 'once'"
  def repeat = rule.repeat

  type :string
  def time_zone = rule.time_zone

  type :number, optional: true
  def start_day = rule.start_day

  type :string, optional: true
  def start_time = rule.start_time

  type :number, optional: true
  def end_day = rule.end_day

  type :string, optional: true
  def end_time = rule.end_time

  # A date and time on the window's own clock, as a date and time field gives it.
  type :string, optional: true
  def starts_at = rule.starts_at

  type :string, optional: true
  def ends_at = rule.ends_at

  type :string, optional: true
  def lifted_by = rule.lifted_by

  # Such as "Changes are frozen every Friday from 15:00 to Monday 08:00 (Europe/Berlin), for Friday afternoons."
  type :string
  def sentence = rule.sentence

  # Whether changes are frozen by it now.
  type :boolean
  def active = rule.occurrences(Time.current).any? { |window| window.covers?(Time.current) }
end
