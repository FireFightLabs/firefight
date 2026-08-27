require "test_helper"

class Webhooks::DeliveryJobTest < ActiveSupport::TestCase
  test "calls delivery service" do
    delivery = webhook_deliveries(:pending_delivery)
    Webhooks::DeliveryService.expects(:deliver).with(delivery)

    Webhooks::DeliveryJob.perform_now(delivery)
  end
end
