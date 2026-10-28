# Every few minutes, checks the subscription proxy is up and keeps workspaces apart (SubscriptionProxy::HealthCheck).
class SubscriptionProxyHealthJob < ApplicationJob
  queue_as :background

  def perform = SubscriptionProxy::HealthCheck.run
end
