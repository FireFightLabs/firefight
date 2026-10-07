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

  # Why the last daily read of the usual log lines failed, or nil.
  type :string, optional: true
  def log_patterns_error = row.log_patterns_error

  # Whether the provider's changes reach the map between sweeps, null for a provider that cannot say what changed.
  type "{ on: boolean; lastEventAt: string | null; reason: string | null } | null"
  def live_updates
    state = row.live_updates
    state && { on: state.on, lastEventAt: state.last_event_at&.utc&.iso8601, reason: state.reason }
  end
end
