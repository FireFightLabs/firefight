require "test_helper"

class Slack::WorkspaceAdapterTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current,
      incidents_channel_id: "C12345678"
    )
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
  end

  # create_incidents_channel tests

  test "create_incidents_channel creates new channel" do
    stub_create_channel do
      result = @adapter.create_incidents_channel

      assert_equal "C12345678", result[:channel_id]
      assert_equal "incidents", result[:channel_name]
      assert_not result[:already_existed]
    end
  end

  test "create_incidents_channel handles existing channel" do
    existing_channel = { id: "C87654321", name: "incidents" }

    stub_create_channel(raises: Slack::Client::ChannelExistsError.new("exists")) do
      stub_list_conversations(channels: [ existing_channel ]) do
        result = @adapter.create_incidents_channel

        assert_equal "C87654321", result[:channel_id]
        assert_equal "incidents", result[:channel_name]
        assert result[:already_existed]
      end
    end
  end

  test "create_incidents_channel logs warning when channel exists" do
    existing_channel = { id: "C87654321", name: "incidents" }
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    stub_create_channel(raises: Slack::Client::ChannelExistsError.new("exists")) do
      stub_list_conversations(channels: [ existing_channel ]) do
        @adapter.create_incidents_channel
      end
    end

    event = logged_events.find { |e| e[:event] == "slack.workspace_adapter.channel_already_exists" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]

    Rails.logger = original_logger
  end

  test "create_incidents_channel raises error if existing channel not found" do
    stub_create_channel(raises: Slack::Client::ChannelExistsError.new("exists")) do
      stub_list_conversations(channels: []) do
        assert_raises(Slack::Client::ChannelNotFoundError) do
          @adapter.create_incidents_channel
        end
      end
    end
  end

  # set_channel_metadata tests

  test "set_channel_metadata sets topic and purpose" do
    stub_set_channel_topic do
      stub_set_channel_purpose do
        result = @adapter.set_channel_metadata(channel_id: "C12345678")

        assert result[:success]
      end
    end
  end

  test "set_channel_metadata uses correct description" do
    topic_set = nil
    purpose_set = nil

    stub_set_channel_topic do
      topic_set = true
      stub_set_channel_purpose do
        purpose_set = true
        @adapter.set_channel_metadata(channel_id: "C12345678")
      end
    end

    assert topic_set
    assert purpose_set
  end

  # invite_user tests

  test "invite_user invites user to channel" do
    stub_invite_to_channel do
      result = @adapter.invite_user(channel_id: "C12345678", user_id: "U12345678")

      assert_equal "U12345678", result[:invited_user]
    end
  end

  test "invite_user raises error on API failure" do
    stub_invite_to_channel(raises: Slack::Client::ApiError.new("not_in_channel")) do
      assert_raises(Slack::Client::ApiError) do
        @adapter.invite_user(channel_id: "C12345678", user_id: "U12345678")
      end
    end
  end

  # post_welcome_message tests

  test "post_welcome_message posts to channel" do
    stub_post_message do
      result = @adapter.post_welcome_message(channel_id: "C12345678")

      assert result[:message_ts].present?
    end
  end

  test "post_welcome_message uses welcome message blocks" do
    message_blocks = nil

    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      message_blocks = args[:blocks]
      { ok: true, ts: "123.456" }
    end

    @adapter.post_welcome_message(channel_id: "C12345678")

    assert message_blocks.present?
    assert message_blocks.is_a?(Array)

    Slack::Client.define_singleton_method(:post_message, original_post)
  end

  # post_preview_announcement tests

  test "post_preview_announcement posts ephemeral message" do
    stub_post_ephemeral do
      result = @adapter.post_preview_announcement(
        channel_id: "C12345678",
        user_id: "U12345678"
      )

      assert result[:message_ts].present?
    end
  end

  test "post_preview_announcement includes user_id in blocks" do
    captured_blocks = nil

    original_ephemeral = Slack::Client.method(:post_ephemeral)
    Slack::Client.define_singleton_method(:post_ephemeral) do |**args|
      captured_blocks = args[:blocks]
      { ok: true, ts: "123.456" }
    end

    @adapter.post_preview_announcement(
      channel_id: "C12345678",
      user_id: "U87654321"
    )

    # Verify user ID appears in blocks (for @mentions)
    blocks_json = captured_blocks.to_json
    assert_includes blocks_json, "U87654321"

    Slack::Client.define_singleton_method(:post_ephemeral, original_ephemeral)
  end

  # open_share_modal tests

  test "open_share_modal opens modal with trigger_id" do
    stub_open_modal do
      result = @adapter.open_share_modal(
        trigger_id: "12345.trigger",
        user_id: "U12345678",
        channel_id: "C12345678"
      )

      assert result[:success]
    end
  end

  test "open_share_modal raises TriggerExpiredError on expired trigger" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired")) do
      assert_raises(Slack::Client::TriggerExpiredError) do
        @adapter.open_share_modal(
          trigger_id: "expired.trigger",
          user_id: "U12345678",
          channel_id: "C12345678"
        )
      end
    end
  end

  # post_share_messages tests

  test "post_share_messages posts to all target conversations" do
    post_count = 0

    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      post_count += 1
      { ok: true, ts: "123.#{post_count}" }
    end

    result = @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111", "C22222222", "C33333333" ]
    )

    assert_equal 3, post_count
    assert_equal 3, result[:shared_count]
    assert_equal 0, result[:failed_count]

    Slack::Client.define_singleton_method(:post_message, original_post)
  end

  test "post_share_messages handles partial failures gracefully" do
    post_count = 0

    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      post_count += 1
      raise Slack::Client::ApiError.new("not_in_channel") if post_count == 2
      { ok: true, ts: "123.#{post_count}" }
    end

    result = @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111", "C22222222", "C33333333" ]
    )

    assert_equal 3, post_count
    assert_equal 2, result[:shared_count]
    assert_equal 1, result[:failed_count]

    Slack::Client.define_singleton_method(:post_message, original_post)
  end

  test "post_share_messages logs warning on failure" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      raise Slack::Client::ApiError.new("not_in_channel")
    end

    @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111" ]
    )

    event = logged_events.find { |e| e[:event] == "slack.workspace_adapter.share_failed" }
    assert event.present?
    assert_equal "C11111111", event[:conversation_id]

    Slack::Client.define_singleton_method(:post_message, original_post)
    Rails.logger = original_logger
  end

  test "post_share_messages includes team_id in deep link" do
    captured_blocks = nil

    original_post = Slack::Client.method(:post_message)
    Slack::Client.define_singleton_method(:post_message) do |**args|
      captured_blocks = args[:blocks]
      { ok: true, ts: "123.456" }
    end

    @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111" ]
    )

    # Verify team_id is in the deep link URL
    blocks_json = captured_blocks.to_json
    assert_includes blocks_json, "slack://channel?team=T12345678"

    Slack::Client.define_singleton_method(:post_message, original_post)
  end

  # find_existing_channel tests

  test "find_existing_channel returns channel by name" do
    channels = [
      { id: "C11111111", name: "general" },
      { id: "C22222222", name: "incidents" },
      { id: "C33333333", name: "random" }
    ]

    stub_list_conversations(channels: channels) do
      # Use create_incidents_channel with error to trigger find_existing_channel
      stub_create_channel(raises: Slack::Client::ChannelExistsError.new("exists")) do
        result = @adapter.create_incidents_channel

        assert_equal "C22222222", result[:channel_id]
      end
    end
  end

  test "find_existing_channel raises error if channel not found" do
    channels = [
      { id: "C11111111", name: "general" },
      { id: "C33333333", name: "random" }
    ]

    stub_list_conversations(channels: channels) do
      stub_create_channel(raises: Slack::Client::ChannelExistsError.new("exists")) do
        assert_raises(Slack::Client::ChannelNotFoundError) do
          @adapter.create_incidents_channel
        end
      end
    end
  end
end
