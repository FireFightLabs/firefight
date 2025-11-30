class RefreshSlackTokensJob < ApplicationJob
  queue_as :default

  # Refresh tokens that expire in the next 3 hours (gives buffer time to fix issues)
  REFRESH_BUFFER = 3.hours

  def perform
    service = Slack::TokenRefreshService.new
    service.refresh_all_expiring(buffer: REFRESH_BUFFER)
  end
end
