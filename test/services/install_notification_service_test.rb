require "test_helper"

class InstallNotificationServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @installer = workspace_memberships(:alice_workspace_one)
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
  end

  test "configured only when the webhook url is set" do
    assert InstallNotificationService.configured?

    Rails.configuration.x.install_notification_webhook_url = nil
    assert_not InstallNotificationService.configured?
  end

  test "posts the workspace, the platform id and the installer with their email" do
    sent = nil
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    http = mock("http")
    http.expects(:request).with { |request| sent = request }.returns(ok)
    Net::HTTP.expects(:start).with("hooks.example.test", 443, has_entries(use_ssl: true)).yields(http).returns(ok)

    InstallNotificationService.new.notify(@workspace, @installer)

    body = JSON.parse(sent.body)
    assert_includes body["text"], @workspace.name
    assert_includes body["text"], @installer.email
    assert_equal @workspace.platform_id, body["platform_id"]
    assert_equal @installer.display_name, body["installer_name"]
  end

  test "a non-success response is a delivery failure" do
    Net::HTTP.stubs(:start).returns(Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error"))

    assert_raises(InstallNotificationService::DeliveryFailed) do
      InstallNotificationService.new.notify(@workspace, @installer)
    end
  end
end
