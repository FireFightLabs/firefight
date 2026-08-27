# Test helper for stubbing Slack::Client API calls using Mocha
#
# Mocha automatically unstubs methods after each test, providing thread-safe
# test isolation for parallel execution.
#
# IMPORTANT: Do not nest these stub calls! Call them sequentially instead:
#   stub_create_channel
#   stub_set_channel_topic
#   # test code here
module SlackClientStubHelper
  # Stub Slack::Client.create_channel
  #
  # @param result [Hash] Result to return
  # @param raises [Class] Exception class to raise (optional)
  def stub_create_channel(result: nil, raises: nil)
    if raises
      Slack::Client.stubs(:create_channel).raises(raises)
    elsif result
      Slack::Client.stubs(:create_channel).returns(result)
    else
      # Return a fixed result for incidents channel
      Slack::Client.stubs(:create_channel).returns(
        channel: { id: "C12345678", name: "incidents", is_channel: true, is_private: false }
      )
    end
  end

  def stub_set_channel_topic
    Slack::Client.stubs(:set_channel_topic).returns({ ok: true, topic: "test topic" })
  end

  def stub_set_channel_purpose
    Slack::Client.stubs(:set_channel_purpose).returns({ ok: true, purpose: "test purpose" })
  end

  def stub_invite_to_channel(raises: nil)
    if raises
      Slack::Client.stubs(:invite_to_channel).raises(raises)
    else
      Slack::Client.stubs(:invite_to_channel).returns({ ok: true, channel: "C12345678" })
    end
  end

  def stub_post_message(raises: nil)
    if raises
      Slack::Client.stubs(:post_message).raises(raises)
    else
      Slack::Client.stubs(:post_message).returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })
    end
  end

  def stub_post_direct_message
    Slack::Client.stubs(:post_message).returns({ ok: true, ts: "1234567890.123456" })
  end

  def stub_post_ephemeral
    Slack::Client.stubs(:post_ephemeral).returns({ ok: true, ts: "1234567890.123456" })
  end

  def stub_open_modal(raises: nil)
    if raises
      Slack::Client.stubs(:open_modal).raises(raises)
    else
      Slack::Client.stubs(:open_modal).returns({ ok: true, view: { id: "V12345678" } })
    end
  end

  def stub_push_modal(raises: nil)
    if raises
      Slack::Client.stubs(:push_modal).raises(raises)
    else
      Slack::Client.stubs(:push_modal).returns({ ok: true, view: { id: "V12345678" } })
    end
  end

  def stub_list_conversations(channels: [])
    Slack::Client.stubs(:list_conversations).returns(channels)
  end

  def stub_pin_message
    Slack::Client.stubs(:pin_message).returns({ ok: true })
  end

  def stub_update_message(raises: nil)
    if raises
      Slack::Client.stubs(:update_message).raises(raises)
    else
      Slack::Client.stubs(:update_message).returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })
    end
  end

  def stub_delete_message
    Slack::Client.stubs(:delete_message).returns({ ok: true, ts: "1234567890.123456", channel: "C12345678" })
  end

  def stub_archive_channel(raises: nil)
    if raises
      Slack::Client.stubs(:archive_channel).raises(raises)
    else
      Slack::Client.stubs(:archive_channel).returns({ ok: true })
    end
  end

  def stub_update_modal(raises: nil)
    if raises
      Slack::Client.stubs(:update_modal).raises(raises)
    else
      Slack::Client.stubs(:update_modal).returns({ ok: true, view: { id: "V12345678" } })
    end
  end

  def stub_get_permalink(permalink: "https://workspace.slack.com/archives/C12345678/p1234567890123456")
    Slack::Client.stubs(:get_permalink).returns({ ok: true, permalink: permalink })
  end

  def stub_get_message(text: "Test message")
    Slack::Client.stubs(:get_message).returns({ "text" => text, "user" => "U12345678", "ts" => "1234567890.123456" })
  end

  def stub_download_file(body: "file-content", content_type: "application/octet-stream")
    Slack::Client.stubs(:download_file).returns({ body: body, content_type: content_type })
  end

  def stub_get_user_info(raises: nil)
    if raises
      Slack::Client.stubs(:get_user_info).raises(raises)
    else
      Slack::Client.stubs(:get_user_info).returns({
        user: {
          id: "U_NEW_USER",
          name: "newuser",
          profile: {
            real_name: "New User",
            display_name: "newuser",
            email: "newuser@example.com"
          }
        }
      })
    end
  end

  def stub_successful_slack_workflow
    stub_create_channel
    stub_set_channel_topic
    stub_set_channel_purpose
    stub_invite_to_channel
    stub_post_message
    stub_pin_message
  end
end
