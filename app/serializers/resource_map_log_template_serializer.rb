# One kind of line a resource usually logs, with numbers, ids and quoted values masked, for the map page.
class ResourceMapLogTemplateSerializer < BaseSerializer
  object_as :pattern

  type :string
  def id = pattern.id

  type :string
  def template = pattern.template

  # error or warning, or nil for any other line.
  type "ResourceMapLogLevel", optional: true
  def level = pattern.level

  # How many lines of the last read followed it.
  type :number
  def lines = pattern.lines

  # How many daily reads saw it in the last week.
  type :number
  def samples = pattern.samples
end
