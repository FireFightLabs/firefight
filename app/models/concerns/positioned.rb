module Positioned
  extend ActiveSupport::Concern

  MAX_POSITION_RETRIES = 5

  class_methods do
    # Renumbers the workspace's rows to 1..N in the order given. Ids missing
    # from ordered_ids keep their relative order at the end, so a partial list
    # cannot silently drop rows, and ids from another workspace are ignored.
    def reorder!(workspace, ordered_ids)
      scope = workspace.public_send(table_name)
      known = scope.order(:position).pluck(:id)
      requested = ordered_ids.map(&:to_s).select { |id| known.include?(id) }
      final = requested + (known - requested)
      return if final.empty?

      transaction do
        # The unique [workspace_id, position] index rules out writing final
        # positions in place, so park every row out of range first.
        scope.update_all("position = -position - 1")
        final.each_with_index do |id, index|
          scope.where(id: id).update_all(position_attributes(index, final.size))
        end
      end
    end

    # Hook for models that mirror the ordering into another column.
    def position_attributes(index, _total)
      { position: index + 1 }
    end
  end

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
