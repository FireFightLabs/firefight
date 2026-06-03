module Positioned
  extend ActiveSupport::Concern

  MAX_POSITION_RETRIES = 5

  # Assigns the next position within the record's workspace scope and saves.
  # Relies on a unique [workspace_id, position] index as the race-stop and
  # retries on RecordNotUnique. Without retry, two concurrent admin clicks
  # could both read max=N and try to write position=N+1.
  def save_in_position!
    attempts = 0
    begin
      attempts += 1
      self.position = (peer_scope.maximum(:position) || 0) + 1
      save!
    rescue ActiveRecord::RecordNotUnique
      raise if attempts >= MAX_POSITION_RETRIES
      retry
    end
  end

  private

  def peer_scope
    workspace.public_send(self.class.table_name)
  end
end
