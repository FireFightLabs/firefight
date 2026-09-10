module Positioned
  extend ActiveSupport::Concern

  MAX_POSITION_RETRIES = 5

  class_methods do
    # Ids missing from ordered_ids keep their order at the end, so a partial
    # list cannot drop rows. Ids from another workspace are ignored.
    def reorder!(workspace, ordered_ids)
      scope = where(workspace_id: workspace.id)
      known = scope.order(:position).pluck(:id)
      requested = ordered_ids.map(&:to_s).select { |id| known.include?(id) }
      final = requested + (known - requested)
      return if final.empty?

      transaction do
        # The unique index on position rules out writing final positions in
        # place, so park every row out of range first.
        scope.update_all("position = -position - 1")
        scope.update_all(position_assignment_sql(final))
      end
    end

    # Overridden by models that mirror the ordering into another column.
    def position_columns(index, _total)
      { position: index + 1 }
    end

    private

    def position_assignment_sql(ordered_ids)
      columns = position_columns(0, ordered_ids.size).keys

      columns.map { |column|
        cases = ordered_ids.each_with_index.map { |id, index|
          "WHEN #{connection.quote(id)} THEN #{connection.quote(position_columns(index, ordered_ids.size).fetch(column))}"
        }
        "#{connection.quote_column_name(column)} = CASE id #{cases.join(' ')} END"
      }.join(", ")
    end
  end

  # The unique index on position is the race stop. Two concurrent clicks can
  # both read max N and try N+1, so the loser retries.
  def save_in_position!
    attempts = 0
    begin
      attempts += 1
      self.position = (peer_scope.maximum(:position) || 0) + 1
      save!
    rescue ActiveRecord::RecordNotUnique
      raise if attempts >= MAX_POSITION_RETRIES
      # The index that fired may be the slug's. Revalidate so a name collision
      # reports on the name instead of retrying into a 500.
      raise ActiveRecord::RecordInvalid.new(self) unless valid?

      retry
    end
  end

  private

  def peer_scope
    self.class.where(workspace_id: workspace_id)
  end
end
