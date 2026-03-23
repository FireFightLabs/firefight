require "test_helper"

class Webhooks::DeliveryJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_events,
           :webhooks, :webhook_delinquency_trackers, :webhook_deliveries

  test "calls delivery service" do
    delivery = webhook_deliveries(:pending_delivery)
    Webhooks::DeliveryService.expects(:deliver).with(delivery)

    Webhooks::DeliveryJob.perform_now(delivery)
  end
end
