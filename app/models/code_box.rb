# One sandbox a run reads code in, from the moment it starts until it is stopped. The box itself lives with a provider,
# this row is how the app finds it again and knows which repositories it already holds.
class CodeBox < ApplicationRecord
  # A chat's box outlives a question, so the next one in the same conversation reads straight away.
  IDLE_AFTER = 15.minutes
  # Nothing holds a box this long without using it, whatever started it.
  ABANDONED_AFTER = 1.hour

  belongs_to :workspace

  encrypts :secret

  scope :live, -> { where(stopped_at: nil) }
  scope :idle, -> { live.where(last_used_at: ...IDLE_AFTER.ago) }
  scope :abandoned, -> { live.where(last_used_at: ...ABANDONED_AFTER.ago) }

  # One statement, so two workers stopping the same box agree on who did it.
  def stop!
    moved = self.class.where(id: id, stopped_at: nil).update_all(stopped_at: Time.current, updated_at: Time.current) > 0
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
