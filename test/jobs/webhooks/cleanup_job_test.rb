require "test_helper"

class Webhooks::CleanupJobTest < ActiveSupport::TestCase
  test "deletes stale deliveries" do
    delivery = webhook_deliveries(:completed_delivery)
    delivery.update_columns(created_at: 8.days.ago)

    WebhookDelivery.expects(:cleanup).once

    Webhooks::CleanupJob.perform_now
  end
end
