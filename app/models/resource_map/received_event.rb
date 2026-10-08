# A change event a connection's provider sent or its change log held, kept a week so a second delivery of the same one
# is a no-op and the activity of live updates can be read back. outcome is nil while it waits to be read again.
class ResourceMap::ReceivedEvent < ApplicationRecord
  self.table_name = "resource_map_events"

  # Read again and written onto the map.
  OUTCOME_APPLIED = "applied".freeze
  # The scope could not be read on its own, so the connection was swept in full.
  OUTCOME_SWEPT = "swept".freeze
  # The provider asked Firefight to slow down, so the next sweep reads it.
  OUTCOME_DEFERRED = "deferred".freeze
  # The re-read failed, so the next sweep reads it.
  OUTCOME_FAILED = "failed".freeze
  # Taken by a job reading it again.
  OUTCOME_READING = "reading".freeze
  OUTCOMES = [ OUTCOME_APPLIED, OUTCOME_SWEPT, OUTCOME_DEFERRED, OUTCOME_FAILED, OUTCOME_READING ].freeze

  KEPT_FOR = 7.days

  belongs_to :workspace
  belongs_to :integration_environment

  validates :action, inclusion: { in: ResourceMap::Event::ACTIONS }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :waiting, -> { where(outcome: nil) }

  def scope_read = ResourceMap::Scope.from_job(scope)

  # Takes every event waiting on this scope for one reader, so a burst of them is read again once. Rows another reader
  # holds are skipped, and the update names the waiting state, so no event is taken twice.
  def self.claim!(environment_row, scope_key)
    transaction do
      ids = waiting.where(integration_environment_id: environment_row.id, scope_key: scope_key).lock("FOR UPDATE SKIP LOCKED").pluck(:id)
      where(id: ids, outcome: nil).update_all(outcome: OUTCOME_READING, updated_at: Time.current)
      where(id: ids, outcome: OUTCOME_READING).to_a
    end
  end

  # Longer than any re-read of one scope takes, so a row still being read after it belongs to a reader whose worker stopped.
  READ_LEASE = 15.minutes

  # Handed to the next sweep, which reads the whole connection, as a failed re-read is. Once, since the update names
  # the reading state.
  def self.give_up_interrupted!
    where(outcome: OUTCOME_READING, updated_at: ...READ_LEASE.ago).update_all(outcome: OUTCOME_FAILED, updated_at: Time.current)
  end

  def self.finish!(events, outcome)
    where(id: events.map(&:id), outcome: OUTCOME_READING).update_all(outcome: outcome, applied_at: Time.current, updated_at: Time.current)
  end
end
