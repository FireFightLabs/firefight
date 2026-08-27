class RefreshPlatformCredentialsJob < ApplicationJob
  queue_as :default

  # Credentials expiring in the next 3 hours, leaving time to notice a failure.
  REFRESH_BUFFER = 3.hours

  def perform
    WorkspaceAdapter.refresh_expiring_credentials(buffer: REFRESH_BUFFER)
  end
end
