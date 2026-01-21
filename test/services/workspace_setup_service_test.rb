require "test_helper"

class WorkspaceSetupServiceTest < ActiveSupport::TestCase
  setup do
    @service = WorkspaceSetupService.new
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current
    )
  end

  # create_incidents_channel tests

  test "create_incidents_channel creates new channel successfully" do
    stub_create_channel do
      result = @service.create_incidents_channel(@workspace)

      assert result[:channel_id].present?
      assert_equal "incidents", result[:channel_name]
      assert_not result[:already_existed]
    end
  end

  test "create_incidents_channel handles existing channel" do
    existing_channel = { id: "C87654321", name: "incidents" }

    stub_create_channel(raises: Slack::Client::ChannelExistsError.new("Channel exists")) do
      stub_list_conversations(channels: [ existing_channel ]) do
        result = @service.create_incidents_channel(@workspace)

        assert_equal "C87654321", result[:channel_id]
        assert_equal "incidents", result[:channel_name]
        assert result[:already_existed]
      end
    end
  end

  test "create_incidents_channel logs creation event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_create_channel do
      @service.create_incidents_channel(@workspace)
    end

    event = logged_events.find { |e| e[:event] == "workspace_setup.channel_created" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]

    Rails.logger = original_logger
  end

  # set_channel_metadata tests

  test "set_channel_metadata sets topic and purpose" do
    stub_set_channel_topic do
      stub_set_channel_purpose do
        result = @service.set_channel_metadata(@workspace, "C12345678")

        assert result[:success]
      end
    end
  end

  test "set_channel_metadata logs success event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_set_channel_topic do
      stub_set_channel_purpose do
        @service.set_channel_metadata(@workspace, "C12345678")
      end
    end

    event = logged_events.find { |e| e[:event] == "workspace_setup.metadata_set" }
    assert event.present?
    assert_equal "C12345678", event[:channel_id]

    Rails.logger = original_logger
  end

  # invite_user tests

  test "invite_user invites user to channel" do
    stub_invite_to_channel do
      result = @service.invite_user(@workspace, "C12345678", "U12345678")

      assert_equal "U12345678", result[:invited_user]
      assert_not result[:skipped]
    end
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

    stub_invite_to_channel do
      @service.invite_user(@workspace, "C12345678", "U12345678")
    end

    event = logged_events.find { |e| e[:event] == "workspace_setup.user_invited" }
    assert event.present?
    assert_equal "U12345678", event[:user_id]

    Rails.logger = original_logger
  end

  # post_welcome_message tests

  test "post_welcome_message posts message to channel" do
    stub_post_message do
      result = @service.post_welcome_message(@workspace, "C12345678")

      assert result[:message_ts].present?
    end
  end

  test "post_welcome_message logs event" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:info) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_post_message do
      @service.post_welcome_message(@workspace, "C12345678")
    end

    event = logged_events.find { |e| e[:event] == "workspace_setup.welcome_posted" }
    assert event.present?
    assert_equal "C12345678", event[:channel_id]

    Rails.logger = original_logger
  end

  # store_channel_id tests

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
    # Make workspace invalid
    @workspace.platform_id = nil

    assert_raises(ActiveRecord::RecordInvalid) do
      @service.store_channel_id(@workspace, "C12345678")
    end
  end

  # Integration test

  test "full workspace setup flow creates channel and sets metadata" do
    stub_create_channel do
      stub_set_channel_topic do
        stub_set_channel_purpose do
          stub_invite_to_channel do
            stub_post_message do
              # Create channel
              create_result = @service.create_incidents_channel(@workspace)
              channel_id = create_result[:channel_id]

              # Set metadata
              metadata_result = @service.set_channel_metadata(@workspace, channel_id)
              assert metadata_result[:success]

              # Post welcome
              welcome_result = @service.post_welcome_message(@workspace, channel_id)
              assert welcome_result[:message_ts].present?

              # Invite user
              invite_result = @service.invite_user(@workspace, channel_id, "U12345678")
              assert_equal "U12345678", invite_result[:invited_user]

              # Store channel
              store_result = @service.store_channel_id(@workspace, channel_id)
              assert_equal channel_id, store_result[:channel_id]

              # Verify workspace was updated
              @workspace.reload
              assert_equal channel_id, @workspace.incidents_channel_id
            end
          end
        end
      end
    end
  end
end
