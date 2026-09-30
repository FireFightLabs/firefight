# A connection's last sweep, and what it could not read.
class ResourceMapConnectionSerializer < BaseSerializer
  object_as :row

  type :string
  def id = row.id

  type :string
  def name = row.integration.name

  type :string, optional: true
  def swept_at = row.map_swept_at&.utc&.iso8601

  type :string, optional: true
  def error = row.map_error

  type "string[]"
  def gaps = row.map_gaps

  # Why the last daily read of what normal looks like failed, or nil.
  type :string, optional: true
  def baseline_error = row.baseline_error
end
