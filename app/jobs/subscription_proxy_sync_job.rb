# Every few minutes, reads how much of each workspace's subscriptions is left, whether their sign-ins still work, and
# the models they serve, and orders each subscription's sign-ins (SubscriptionProxy::Accounts).
class SubscriptionProxySyncJob < ApplicationJob
  queue_as :background

  def perform = SubscriptionProxy::Accounts.sync_all!
end
