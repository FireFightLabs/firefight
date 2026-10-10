# One sandbox a run reads code in, from the moment it starts until it is stopped. The box itself lives with a provider,
# this row is how the app finds it again and knows which repositories it already holds.
class CodeBox < ApplicationRecord
  # A chat's box outlives a question, so the next one in the same conversation reads straight away.
  IDLE_AFTER = 15.minutes
  # Nothing holds a box this long without using it, whatever started it.
  ABANDONED_AFTER = 1.hour
  # What the sandbox can start inside a box for a repository's tests.
  SERVICES = %w[postgres redis].freeze

  belongs_to :workspace

  encrypts :secret, :address_query

  scope :live, -> { where(stopped_at: nil) }
  scope :idle, -> { live.where(last_used_at: ...IDLE_AFTER.ago) }
  scope :abandoned, -> { live.where(last_used_at: ...ABANDONED_AFTER.ago) }

  # One statement, so two workers stopping the same box agree on who did it. The time it ran is added in the same
  # statement, from when the provider's box under this row started.
  def stop!
    now = Time.current
    moved = self.class.where(id: id, stopped_at: nil).update_all(
      [ "stopped_at = :now, updated_at = :now, running_seconds = running_seconds + GREATEST(0, EXTRACT(EPOCH FROM (:now - COALESCE(box_started_at, created_at))))::integer",
        { now: now } ]
    ) > 0
    reload if moved
    moved
  end

  # A provider's address can carry a token in its query, such as the one a proxy in front of the box asks for, which is
  # kept encrypted apart from the address.
  def self.address_columns(full)
    base, query = full.to_s.split("?", 2)
    { address: base, address_query: query.presence }
  end

  def self.encrypted(attribute, value) = value && type_for_attribute(attribute).serialize(value)

  def reach_address = address_query.present? ? "#{address}?#{address_query}" : address

  # The provider's box under this row was replaced by another one, such as a copy of a prepared repository. The time
  # the old one ran is kept and the clock starts again for the new one, in one statement guarded by the box it leaves,
  # so a row stopped or moved meanwhile is left alone and the answer says so.
  def moved_to!(started, hourly_micros:)
    columns = self.class.address_columns(started.address)
    moved = self.class.where(id: id, stopped_at: nil, box_ref: box_ref).update_all(
      [ "box_ref = :ref, address = :address, address_query = :query, secret = :secret, hourly_micros = :hourly, repositories = '{}'::jsonb, " \
        "box_started_at = :now, updated_at = :now, " \
        "running_seconds = running_seconds + GREATEST(0, EXTRACT(EPOCH FROM (:now - COALESCE(box_started_at, created_at))))::integer",
        { ref: started.ref, address: columns[:address], query: self.class.encrypted(:address_query, columns[:address_query]),
          secret: self.class.encrypted(:secret, started.key), hourly: hourly_micros, now: Time.current } ]
    ) > 0
    reload if moved
    moved
  end

  def used!
    self.class.where(id: id).update_all(last_used_at: Time.current)
  end

  def holds?(repository) = repositories.key?(repository)

  # Merged in SQL, since two tools can push different repositories into the same box at once.
  def record_repository!(repository, head:, default_branch:)
    entry = { "head" => head, "default_branch" => default_branch, "pushed_at" => Time.current.iso8601 }
    self.class.where(id: id).update_all(
      [ "repositories = repositories || jsonb_build_object(?::text, ?::jsonb), updated_at = now()", repository, entry.to_json ]
    )
    reload
  end
end
