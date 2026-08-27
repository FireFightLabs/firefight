class CleanupIdempotencyKeysJob < ApplicationJob
  queue_as :default

  def perform
    IdempotencyKey.cleanup
  end
end
