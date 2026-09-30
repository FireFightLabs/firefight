# What normal looks like for one metric of a resource over the last week, each amount written with its unit.
class ResourceMapBaselineSerializer < BaseSerializer
  object_as :baseline

  type :string
  def id = baseline.id

  type :string
  def label = baseline.label

  type :string
  def typical = baseline.typical_text

  type :string
  def high = baseline.high_text

  type :string
  def peak = baseline.peak_text

  type :string
  def window_to = baseline.window_to.utc.iso8601
end
