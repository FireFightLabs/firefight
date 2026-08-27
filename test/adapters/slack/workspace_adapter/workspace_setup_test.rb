require "test_helper"

class Slack::WorkspaceAdapter::WorkspaceSetupTest < ActiveSupport::TestCase
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
    stub_create_channel
    result = @adapter.create_incidents_channel

    assert_equal "C12345678", result[:channel_id]
    assert_equal "incidents", result[:channel_name]
    assert_not result[:already_existed]
  end

  test "create_incidents_channel handles existing channel" do
    existing_channel = { id: "C87654321", name: "incidents" }

    stub_create_channel(raises: AdapterError::ChannelExists.new("exists"))
      stub_list_conversations(channels: [ existing_channel ])
      result = @adapter.create_incidents_channel

      assert_equal "C87654321", result[:channel_id]
      assert_equal "incidents", result[:channel_name]
      assert result[:already_existed]
  end

  test "create_incidents_channel logs warning when channel exists" do
    existing_channel = { id: "C87654321", name: "incidents" }
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
    logged_events << message if message.is_a?(Hash)
    end

    stub_create_channel(raises: AdapterError::ChannelExists.new("exists"))
      stub_list_conversations(channels: [ existing_channel ])
      @adapter.create_incidents_channel

    event = logged_events.find { |e| e[:event] == "slack.workspace_adapter.channel_already_exists" }
    assert event.present?
    assert_equal @workspace.id, event[:workspace_id]

    Rails.logger = original_logger
  end

  test "create_incidents_channel raises error if existing channel not found" do
    stub_create_channel(raises: AdapterError::ChannelExists.new("exists"))
    stub_list_conversations(channels: [])
    assert_raises(AdapterError::NotFound) do
      @adapter.create_incidents_channel
    end
  end

  # post_welcome_message tests

  test "post_welcome_message posts to channel" do
    stub_post_message
    result = @adapter.post_welcome_message(channel_id: "C12345678")

    assert result[:message_id].present?
  end

  test "post_welcome_message uses welcome message blocks" do
    # Verify post_message is called with blocks argument
    Slack::Client.expects(:post_message).with do |**args|
      args[:blocks].present? && args[:blocks].is_a?(Array)
    end.returns({ ok: true, ts: "123.456" })

    @adapter.post_welcome_message(channel_id: "C12345678")
  end

  # post_preview_announcement tests

  test "post_preview_announcement posts ephemeral message" do
    stub_post_ephemeral
    result = @adapter.post_preview_announcement(
      channel_id: "C12345678",
      user_id: "U12345678"
    )

    assert result[:success]
  end

  test "post_preview_announcement includes user_id in blocks" do
    # Verify post_ephemeral is called with user_id in blocks
    Slack::Client.expects(:post_ephemeral).with do |**args|
      blocks_json = args[:blocks].to_json
      blocks_json.include?("U87654321")
    end.returns({ ok: true, ts: "123.456" })

    @adapter.post_preview_announcement(
      channel_id: "C12345678",
      user_id: "U87654321"
    )
  end

  # open_share_modal tests

  test "open_share_modal opens modal with trigger_id" do
    stub_open_modal
    result = @adapter.open_share_modal(
      trigger_id: "12345.trigger",
      user_id: "U12345678",
      channel_id: "C12345678"
    )

    assert result[:success]
  end

  # post_share_messages tests

  test "post_share_messages posts to all target conversations" do
    # Verify post_message is called 3 times (once per conversation)
    Slack::Client.expects(:post_message).times(3).returns({ ok: true, ts: "123.456" })

    result = @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111", "C22222222", "C33333333" ]
    )

    assert_equal 3, result[:shared_count]
    assert_equal 0, result[:failed_count]
  end

  test "post_share_messages handles partial failures gracefully" do
    # Stub to succeed on 1st call, fail on 2nd, succeed on 3rd
    Slack::Client.stubs(:post_message)
      .returns({ ok: true, ts: "123.1" })
      .then.raises(AdapterError.new("not_in_channel"))
      .then.returns({ ok: true, ts: "123.3" })

    result = @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111", "C22222222", "C33333333" ]
    )

    assert_equal 2, result[:shared_count]
    assert_equal 1, result[:failed_count]
  end

  test "post_share_messages logs warning on failure" do
    logged_events = []
    original_logger = Rails.logger

    Rails.logger = Logger.new(IO::NULL)
    Rails.logger.define_singleton_method(:warn) do |message|
      logged_events << message if message.is_a?(Hash)
    end

    Slack::Client.stubs(:post_message).raises(AdapterError.new("not_in_channel"))

    @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111" ]
    )

    event = logged_events.find { |e| e[:event] == "slack.workspace_adapter.share_failed" }
    assert event.present?
    assert_equal "C11111111", event[:conversation_id]

    Rails.logger = original_logger
  end

  test "post_share_messages includes team_id in deep link" do
    # Verify post_message is called with team_id in deep link
    Slack::Client.expects(:post_message).with do |**args|
      blocks_json = args[:blocks].to_json
      blocks_json.include?("slack://channel?team=#{@workspace.platform_id}")
    end.returns({ ok: true, ts: "123.456" })

    @adapter.post_share_messages(
      user_id: "U12345678",
      channel_id: "C12345678",
      target_conversations: [ "C11111111" ]
    )
  end

  # find_existing_channel tests (tested indirectly through create_incidents_channel)

  test "find_existing_channel returns channel by name" do
    channels = [
    { id: "C11111111", name: "general" },
    { id: "C22222222", name: "incidents" },
    { id: "C33333333", name: "random" }
    ]

    stub_list_conversations(channels: channels)
      # Use create_incidents_channel with error to trigger find_existing_channel
      stub_create_channel(raises: AdapterError::ChannelExists.new("exists"))
      result = @adapter.create_incidents_channel

      assert_equal "C22222222", result[:channel_id]
  end

  test "find_existing_channel raises error if channel not found" do
    channels = [
      { id: "C11111111", name: "general" },
      { id: "C33333333", name: "random" }
    ]

    stub_list_conversations(channels: channels)
    stub_create_channel(raises: AdapterError::ChannelExists.new("exists"))
    assert_raises(AdapterError::NotFound) do
      @adapter.create_incidents_channel
    end
  end
end
