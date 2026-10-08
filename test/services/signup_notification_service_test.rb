require "test_helper"

class SignupNotificationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @installer = workspace_memberships(:alice_workspace_one)
    Rails.configuration.x.install_notification_webhook_url = "https://hooks.example.test/services/T0/B0/x"
  end

  teardown do
    Rails.configuration.x.install_notification_webhook_url = nil
  end

  test "configured only when the webhook url is set" do
    assert SignupNotificationService.configured?

    Rails.configuration.x.install_notification_webhook_url = nil
    assert_not SignupNotificationService.configured?
  end

  test "a new workspace names who created it, their email and how they signed in" do
    body = deliver(SignupNotificationService::WORKSPACE_CREATED, sign_up_method: UserIdentity::GOOGLE)

    assert_equal "New workspace: #{@workspace.name}, created by #{@installer.display_name} (#{@installer.email}) with Google", body["text"]
    assert_equal SignupNotificationService::WORKSPACE_CREATED, body["event"]
    assert_equal @workspace.platform_id, body["platform_id"]
    assert_equal @installer.display_name, body["installer_name"]
    assert_equal @installer.email, body["installer_email"]
    assert_equal UserIdentity::GOOGLE, body["sign_up_method"]
  end

  test "each sign-in method reads as a phrase" do
    assert_match(/ with an email link\z/, deliver(SignupNotificationService::WORKSPACE_CREATED, sign_up_method: UserIdentity::EMAIL)["text"])
    assert_match(/ with Slack\z/, deliver(SignupNotificationService::WORKSPACE_CREATED, sign_up_method: UserIdentity::SLACK)["text"])
  end

  test "a workspace that connects its chat platform later names the team by its address, or its name without one" do
    @workspace.update!(platform_data: { "id" => @workspace.platform_id, "name" => "Acme HQ", "domain" => "acme" })
    assert_equal "#{@workspace.name} connected Slack (acme.slack.com)", deliver(SignupNotificationService::CHAT_CONNECTED)["text"]

    @workspace.update!(platform_data: { "id" => @workspace.platform_id, "name" => "Acme HQ" })
    assert_equal "#{@workspace.name} connected Slack (Acme HQ)", deliver(SignupNotificationService::CHAT_CONNECTED)["text"]
  end

  test "a workspace without a chat platform still carries its fields" do
    unconnected = Workspace.sign_up!(name: "Plain Co", user: users(:charlie))

    body = deliver(SignupNotificationService::WORKSPACE_CREATED, workspace: unconnected.workspace, member: unconnected)

    assert_equal "New workspace: Plain Co, created by #{unconnected.display_name} (#{unconnected.email})", body["text"]
    assert_nil body["platform"]
    assert_nil body["installed_at"]
  end

  test "a non-success response is a delivery failure" do
    Net::HTTP.stubs(:start).returns(Net::HTTPInternalServerError.new("1.1", "500", "Internal Server Error"))

    assert_raises(SignupNotificationService::DeliveryFailed) do
      SignupNotificationService.new.notify(SignupNotificationService::WORKSPACE_CREATED, @workspace, @installer)
    end
  end

  test "announcing with no webhook set enqueues nothing" do
    Rails.configuration.x.install_notification_webhook_url = nil

    assert_no_enqueued_jobs do
      SignupNotificationService.announce(SignupNotificationService::WORKSPACE_CREATED, @workspace, @installer)
    end
  end

  test "an announcement waits for the transaction, and one that rolls back is never sent" do
    ActiveRecord::Base.transaction do
      SignupNotificationService.announce(SignupNotificationService::WORKSPACE_CREATED, @workspace, @installer)
      raise ActiveRecord::Rollback
    end
    assert_no_enqueued_jobs only: SignupNotificationJob

    assert_enqueued_with(job: SignupNotificationJob, args: [ SignupNotificationService::CHAT_CONNECTED, @workspace.id, @installer.id, nil ]) do
      SignupNotificationService.announce(SignupNotificationService::CHAT_CONNECTED, @workspace, @installer)
    end
  end

  test "an enqueue that fails is logged and never reaches the person signing up" do
    SignupNotificationJob.stubs(:perform_later).raises(ActiveRecord::ConnectionNotEstablished)
    Rails.logger.expects(:warn).with { |payload| payload[:event] == "signup_notification.enqueue_failed" }

    assert_nothing_raised do
      SignupNotificationService.announce(SignupNotificationService::WORKSPACE_CREATED, @workspace, @installer)
    end
  end

  private

  def deliver(event, workspace: @workspace, member: @installer, sign_up_method: nil)
    sent = nil
    ok = Net::HTTPOK.new("1.1", "200", "OK")
    http = mock("http")
    http.expects(:request).with { |request| sent = request }.returns(ok)
    Net::HTTP.expects(:start).with("hooks.example.test", 443, has_entries(use_ssl: true)).yields(http).returns(ok)

    SignupNotificationService.new.notify(event, workspace, member, sign_up_method: sign_up_method)
    JSON.parse(sent.body)
  end
end
