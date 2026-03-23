require "test_helper"

class Webhooks::CleanupJobTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :incident_events,
           :webhooks, :webhook_delinquency_trackers, :webhook_deliveries

  test "deletes stale deliveries" do
    delivery = webhook_deliveries(:completed_delivery)
    delivery.update_columns(created_at: 8.days.ago)

    WebhookDelivery.expects(:cleanup).once

    Webhooks::CleanupJob.perform_now
  end
end
