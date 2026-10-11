# A page in an on-call tool tied to an incident, as the incident page lists it beside its alerts.
class IncidentPageSerializer < BaseSerializer
  object_as :page

  TONE_PAGING = "paging".freeze
  TONE_HANDLED = "handled".freeze
  TONE_PROBLEM = "problem".freeze
  TONES = {
    Incident::Page::STATE_RAISING => TONE_PAGING, Incident::Page::STATE_TRIGGERED => TONE_PAGING,
    Incident::Page::STATE_ACKNOWLEDGED => TONE_HANDLED, Incident::Page::STATE_RESOLVED => TONE_HANDLED,
    Incident::Page::STATE_AWAITING_APPROVAL => TONE_PROBLEM, Incident::Page::STATE_FAILED => TONE_PROBLEM
  }.freeze

  type :string
  def id = page.id

  # The page as a person reads it, such as "#42 in PagerDuty".
  type :string
  def label = page.label.upcase_first

  type :string, optional: true
  def url = page.url

  # Where it stands, in words.
  type :string
  def state_words = page.state_words

  # How the incident page colours it: still paging, taken or over, or held back.
  type TONES.values.uniq.map(&:inspect).join(" | ")
  def tone = TONES.fetch(page.state)

  # Why the tool did not take the last change from here, or null.
  type :string, optional: true
  def note = page.sync_note
end
