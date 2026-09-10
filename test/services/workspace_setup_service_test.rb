require "test_helper"

class WorkspaceSetupServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
    platform: "slack",
    platform_id: "T#{SecureRandom.hex(8)}",
    name: "Test Workspace",
    access_token: "xoxb-test-token",
    installed_at: Time.current
    )
    @service = WorkspaceSetupService.new(@workspace)
  end

  test "create_incidents_channel creates new channel successfully" do
    stub_create_channel

    result = @service.create_incidents_channel(@workspace)

    assert result[:channel_id].present?
    assert_equal "incidents", result[:channel_name]
    assert_not result[:already_existed]
  end

  test "create_incidents_channel handles existing channel" do
    existing_channel = { id: "C87654321", name: "incidents" }

    stub_create_channel(raises: AdapterError::ChannelExists.new("Channel exists"))
    stub_list_conversations(channels: [ existing_channel ])

    result = @service.create_incidents_channel(@workspace)

    assert_equal "C87654321", result[:channel_id]
    assert_equal "incidents", result[:channel_name]
    assert result[:already_existed]
  end

  test "create_incidents_channel logs creation event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    stub_create_channel
    @service.create_incidents_channel(@workspace)

    event = logged_events.find { |e| e[:event] == "workspace_setup.channel_created" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]

    Rails.logger = original_logger
  end

  test "set_channel_metadata sets topic and purpose" do
    stub_set_channel_topic
      stub_set_channel_purpose
      result = @service.set_channel_metadata(@workspace, "C12345678")

      assert result[:success]
  end

  test "set_channel_metadata logs success event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    stub_set_channel_topic
      stub_set_channel_purpose
      @service.set_channel_metadata(@workspace, "C12345678")

    event = logged_events.find { |e| e[:event] == "workspace_setup.metadata_set" }
    assert event.present?
    assert_equal "C12345678", event[:channel_id]

    Rails.logger = original_logger
  end

  test "invite_user invites user to channel" do
    stub_invite_to_channel
    result = @service.invite_user(@workspace, "C12345678", "U12345678")

    assert_equal "U12345678", result[:invited_user]
    assert_not result[:skipped]
  end

  test "invite_user skips invitation if channel already existed" do
    result = @service.invite_user(
    @workspace,
    "C12345678",
    "U12345678",
    skip_if_channel_existed: true
    )

    assert result[:skipped]
    assert_nil result[:invited_user]
  end

  test "invite_user logs skip event when skipped" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    @service.invite_user(
    @workspace,
    "C12345678",
    "U12345678",
    skip_if_channel_existed: true
    )

    event = logged_events.find { |e| e[:event] == "workspace_setup.invite_skipped" }
    assert event.present?
    assert_equal "Skipping user invite, channel already existed", event[:message]

    Rails.logger = original_logger
  end

  test "invite_user logs invitation event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    stub_invite_to_channel
    @service.invite_user(@workspace, "C12345678", "U12345678")

    event = logged_events.find { |e| e[:event] == "workspace_setup.user_invited" }
    assert event.present?
    assert_equal "U12345678", event[:user_id]

    Rails.logger = original_logger
  end

  test "post_welcome_message posts message to channel" do
    stub_post_message
    result = @service.post_welcome_message(@workspace, "C12345678")

    assert result[:message_id].present?
  end

  test "post_welcome_message keeps the message id on the onboarding row" do
    onboarding = @workspace.create_onboarding!
    stub_post_message

    @service.post_welcome_message(@workspace, "C12345678")

    assert_equal "1234567890.123456", onboarding.reload.welcome_message_id
  end

  test "refresh_welcome_message redraws the checklist and completes the onboarding when the loop is done" do
    onboarding = @workspace.create_onboarding!(welcome_message_id: "111.222")
    @workspace.update!(incidents_channel_id: "C12345678")
    WorkspaceOnboarding.any_instance.stubs(:stage).returns(WorkspaceOnboarding::STAGE_DONE)
    Slack::Client.expects(:update_message).with(has_entries(channel: "C12345678", ts: "111.222")).once.returns({ ok: true })

    result = @service.refresh_welcome_message(@workspace)

    assert result[:updated]
    assert onboarding.reload.completed_at.present?
  end

  test "refresh_welcome_message skips a workspace with no message to redraw" do
    @workspace.create_onboarding!

    assert_equal({ skipped: true }, @service.refresh_welcome_message(@workspace))
  end

  test "refresh_welcome_message logs a deleted message and moves on" do
    @workspace.create_onboarding!(welcome_message_id: "111.222")
    @workspace.update!(incidents_channel_id: "C12345678")
    Slack::Client.stubs(:update_message).raises(AdapterError::NotFound.new("message_not_found"))

    assert_equal({ updated: false, stage: WorkspaceOnboarding::STAGE_NONE }, @service.refresh_welcome_message(@workspace))
  end

  test "post_welcome_message logs event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    stub_post_message
    @service.post_welcome_message(@workspace, "C12345678")

    event = logged_events.find { |e| e[:event] == "workspace_setup.welcome_posted" }
    assert event.present?
    assert_equal "C12345678", event[:channel_id]

    Rails.logger = original_logger
  end

  test "store_channel_id saves channel ID to workspace" do
    result = @service.store_channel_id(@workspace, "C12345678")

    assert_equal "C12345678", result[:channel_id]
    assert_equal @workspace.id, result[:workspace_id]
    @workspace.reload
    assert_equal "C12345678", @workspace.incidents_channel_id
  end

  test "store_channel_id logs event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    @service.store_channel_id(@workspace, "C12345678")

    event = logged_events.find { |e| e[:event] == "workspace_setup.channel_stored" }
    assert event.present?
    assert_equal "C12345678", event[:channel_id]

    Rails.logger = original_logger
  end

  test "store_channel_id handles save errors" do
    @workspace.platform_id = nil

    assert_raises(ActiveRecord::RecordInvalid) do
    @service.store_channel_id(@workspace, "C12345678")
    end
  end

  test "full workspace setup flow creates channel and sets metadata" do
    stub_create_channel
      stub_set_channel_topic
        stub_set_channel_purpose
          stub_invite_to_channel
            stub_post_message
            create_result = @service.create_incidents_channel(@workspace)
            channel_id = create_result[:channel_id]

            metadata_result = @service.set_channel_metadata(@workspace, channel_id)
            assert metadata_result[:success]

            welcome_result = @service.post_welcome_message(@workspace, channel_id)
            assert welcome_result[:message_id].present?

            invite_result = @service.invite_user(@workspace, channel_id, "U12345678")
            assert_equal "U12345678", invite_result[:invited_user]

            store_result = @service.store_channel_id(@workspace, channel_id)
            assert_equal channel_id, store_result[:channel_id]

            @workspace.reload
            assert_equal channel_id, @workspace.incidents_channel_id
  end
end
