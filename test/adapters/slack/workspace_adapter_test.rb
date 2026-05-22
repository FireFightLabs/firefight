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

  # create_channel tests

  test "create_channel creates new channel" do
    stub_create_channel(result: { channel: { id: "C_NEW", name: "inc-001-test", is_channel: true } })
    result = @adapter.create_channel(name: "inc-001-test")

    assert_equal "C_NEW", result[:channel_id]
    assert_equal "inc-001-test", result[:channel_name]
  end

  test "create_channel translates ChannelExistsError to AdapterError" do
    stub_create_channel(raises: Slack::Client::ChannelExistsError.new("name_taken"))
    assert_raises(AdapterError::ChannelExists) do
      @adapter.create_channel(name: "existing-channel")
    end
  end

  # set_channel_metadata tests

  test "set_channel_metadata sets topic and purpose" do
    stub_set_channel_topic
    stub_set_channel_purpose
    result = @adapter.set_channel_metadata(channel_id: "C12345678", topic: "my topic", purpose: "my purpose")

    assert result[:success]
  end

  test "set_channel_metadata passes topic and purpose to Slack API" do
    Slack::Client.expects(:set_channel_topic).with(
      workspace: @workspace, channel: "C12345678", topic: "custom topic"
    ).returns({ ok: true })
    Slack::Client.expects(:set_channel_purpose).with(
      workspace: @workspace, channel: "C12345678", purpose: "custom purpose"
    ).returns({ ok: true })

    @adapter.set_channel_metadata(channel_id: "C12345678", topic: "custom topic", purpose: "custom purpose")
  end

  # post_message tests

  test "post_message posts to channel and returns message_id" do
    stub_post_message
    result = @adapter.post_message(channel_id: "C12345678", text: "hello", blocks: [])

    assert_equal "1234567890.123456", result[:message_id]
  end

  # pin_message tests

  test "pin_message pins message in channel" do
    stub_pin_message
    result = @adapter.pin_message(channel_id: "C12345678", message_id: "1234567890.123456")

    assert result[:ok]
  end

  # invite_user tests

  test "invite_user invites user to channel" do
    stub_invite_to_channel
    result = @adapter.invite_user(channel_id: "C12345678", user_id: "U12345678")

    assert_equal "U12345678", result[:invited_user]
  end

  test "invite_user raises error on API failure" do
    stub_invite_to_channel(raises: Slack::Client::ApiError.new("not_in_channel"))
    assert_raises(AdapterError) do
      @adapter.invite_user(channel_id: "C12345678", user_id: "U12345678")
    end
  end

  test "invite_users invites multiple users" do
    Slack::Client.expects(:invite_to_channel).with(
      workspace: @workspace,
      channel: "C12345678",
      users: [ "U11111111", "U22222222" ]
    ).returns({ ok: true })

    result = @adapter.invite_users(channel_id: "C12345678", user_ids: [ "U11111111", "U22222222" ])

    assert_equal [ "U11111111", "U22222222" ], result[:invited_users]
  end

  test "open_modal translates TriggerExpiredError to platform-agnostic error" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    assert_raises(AdapterError::TriggerExpired) do
      @adapter.open_modal(
        trigger_id: "expired.trigger",
        view: { type: "modal" }
      )
    end
  end
end
