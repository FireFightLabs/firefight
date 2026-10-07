# What running a key check from the map page answered, shown under the check.
class ResourceMapCheckOutcomeSerializer < BaseSerializer
  object_as :outcome

  # What was checked, through which connection, and how it compares with normal.
  type :string, optional: true
  def headline = outcome.headline

  type :string, optional: true
  def text = outcome.text

  # The answer's page on the provider, where what it read can be checked at its source.
  type :string, optional: true
  def link = outcome.link

  has_many :charts, serializer: ChatChartSerializer do
    outcome.charts
  end

  type :boolean
  def failed = outcome.failed

  # The approval the call waits for, passed back when it is run again once approved.
  type :string, optional: true
  def approval_id = outcome.approval_id

  # Why it did not run.
  type :string, optional: true
  def refusal = outcome.refusal
end
