# Test helper for stubbing Slack::Client API calls
module SlackClientStubHelper
  # Stub Slack::Client.create_channel
  #
  # @param result [Hash] Result to return
  # @param raises [Class] Exception class to raise (optional)
  def stub_create_channel(result: nil, raises: nil)
    original_method = Slack::Client.method(:create_channel)

    Slack::Client.define_singleton_method(:create_channel) do |**args|
      raise raises if raises
      result || {
        channel: {
          id: "C12345678",
          name: args[:name],
          is_channel: true,
          is_private: args[:is_private]
        }
      }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:create_channel, original_method) if block_given?
  end

  # Stub Slack::Client.set_channel_topic
  def stub_set_channel_topic
    original_method = Slack::Client.method(:set_channel_topic)

    Slack::Client.define_singleton_method(:set_channel_topic) do |**args|
      { ok: true, topic: args[:topic] }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:set_channel_topic, original_method) if block_given?
  end

  # Stub Slack::Client.set_channel_purpose
  def stub_set_channel_purpose
    original_method = Slack::Client.method(:set_channel_purpose)

    Slack::Client.define_singleton_method(:set_channel_purpose) do |**args|
      { ok: true, purpose: args[:purpose] }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:set_channel_purpose, original_method) if block_given?
  end

  # Stub Slack::Client.invite_to_channel
  def stub_invite_to_channel(raises: nil)
    original_method = Slack::Client.method(:invite_to_channel)

    Slack::Client.define_singleton_method(:invite_to_channel) do |**args|
      raise raises if raises
      { ok: true, channel: args[:channel] }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:invite_to_channel, original_method) if block_given?
  end

  # Stub Slack::Client.post_message
  def stub_post_message(raises: nil)
    original_method = Slack::Client.method(:post_message)

    Slack::Client.define_singleton_method(:post_message) do |**args|
      raise raises if raises
      { ok: true, ts: "1234567890.123456", channel: args[:channel] }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:post_message, original_method) if block_given?
  end

  # Stub Slack::Client.post_ephemeral
  def stub_post_ephemeral
    original_method = Slack::Client.method(:post_ephemeral)

    Slack::Client.define_singleton_method(:post_ephemeral) do |**args|
      { ok: true, ts: "1234567890.123456" }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:post_ephemeral, original_method) if block_given?
  end

  # Stub Slack::Client.open_modal
  def stub_open_modal(raises: nil)
    original_method = Slack::Client.method(:open_modal)

    Slack::Client.define_singleton_method(:open_modal) do |**args|
      raise raises if raises
      { ok: true, view: { id: "V12345678" } }
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:open_modal, original_method) if block_given?
  end

  # Stub Slack::Client.list_conversations
  def stub_list_conversations(channels: [])
    original_method = Slack::Client.method(:list_conversations)

    Slack::Client.define_singleton_method(:list_conversations) do |**args|
      channels
    end

    yield if block_given?
  ensure
    Slack::Client.define_singleton_method(:list_conversations, original_method) if block_given?
  end

  # Stub all Slack Client methods for a successful workflow
  def stub_successful_slack_workflow
    stub_create_channel
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_invite_to_channel
    stub_post_message

    yield if block_given?
  end
end
