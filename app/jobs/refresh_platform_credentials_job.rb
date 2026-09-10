class RefreshPlatformCredentialsJob < ApplicationJob
  queue_as :default

  # Leaves time to notice a failed refresh before the credential expires.
  REFRESH_BUFFER = 3.hours

  def perform
    WorkspaceAdapter.refresh_expiring_credentials(buffer: REFRESH_BUFFER)
  end
end
