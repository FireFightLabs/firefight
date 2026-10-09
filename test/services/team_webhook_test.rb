require "test_helper"

class TeamWebhookTest < ActiveSupport::TestCase
  setup { Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x" }
  teardown { Rails.configuration.x.install_notification_webhook_url = nil }

  test "a note names the person it is for at its start, and one with nobody named is sent as written" do
    sent = []
    Net::HTTP.stubs(:start).with { |*| true }.returns(Net::HTTPOK.new("1.1", "200", "OK")).then.returns(Net::HTTPOK.new("1.1", "200", "OK"))
    Net::HTTP::Post.any_instance.stubs(:body=).with { |body| sent << JSON.parse(body) }

    TeamWebhook.post!({ text: "The key is running low." }, mention: "U012AB3CD")
    TeamWebhook.post!({ text: "The key is running low." })

    assert_equal [ "<@U012AB3CD> The key is running low.", "The key is running low." ], sent.map { |payload| payload["text"] }
  end
end
