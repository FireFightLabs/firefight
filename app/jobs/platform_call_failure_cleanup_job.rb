class PlatformCallFailureCleanupJob < ApplicationJob
  queue_as :background

  def perform
    PlatformCallFailure.cleanup
  end
end
