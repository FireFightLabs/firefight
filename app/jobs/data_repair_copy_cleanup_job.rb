# Drops the copies of rows kept before Halon changed them once they were kept for Chat::DataRepair::COPY_KEPT_FOR,
# leaving the counts and the check.
class DataRepairCopyCleanupJob < ApplicationJob
  queue_as :background

  def perform
    Chat::DataRepair.drop_expired_copies!
  end
end
