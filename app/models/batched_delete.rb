class BatchedDelete
  DEFAULT_BATCH_SIZE = 500
  DEFAULT_PAUSE = 0.1

  def self.run(scope, label:, batch_size: DEFAULT_BATCH_SIZE, pause: DEFAULT_PAUSE, metadata: {})
    total = 0

    loop do
      deleted = scope.limit(batch_size).delete_all
      total += deleted
      break if deleted.zero?
      sleep pause
    end

    Rails.logger.info({ event: "#{label}.completed", deleted: total }.merge(metadata))
    total
  end
end
