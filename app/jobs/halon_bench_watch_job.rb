# Settles chat bench scenarios whose worker was lost, so the run they belong to can finish.
class HalonBenchWatchJob < ApplicationJob
  queue_as :background

  def perform
    Conversation::Bench.settle_stale!
  end
end
