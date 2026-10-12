require "test_helper"

# Finding a channel someone named and posting in it as Firefight. A public channel is found by its name, and any
# channel by its id, a mention of it or its link, since Slack never lists a private channel to the app.
class Slack::WorkspaceAdapter::ChannelPostsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
    stub_list_conversations(channels: [ { id: "C0GENERAL1", name: "general" }, { id: "C0RELEASE1", name: "releases" } ])
  end

  test "a public channel is found by its name, with or without its #, in any case" do
    assert_equal({ channel_id: "C0GENERAL1", channel_name: "general" }, @adapter.find_channel(reference: "#general"))
    assert_equal({ channel_id: "C0RELEASE1", channel_name: "releases" }, @adapter.find_channel(reference: " Releases "))
  end

  test "a channel named by its id, a mention or its link is taken as it is, with its name when Slack lists it" do
    assert_equal({ channel_id: "C0RELEASE1", channel_name: "releases" }, @adapter.find_channel(reference: "C0RELEASE1"))
    assert_equal({ channel_id: "G0PRIVATE1", channel_name: "leadership" }, @adapter.find_channel(reference: "<#G0PRIVATE1|leadership>"))
    assert_equal({ channel_id: "G0PRIVATE1", channel_name: nil }, @adapter.find_channel(reference: "<#G0PRIVATE1>"))
    assert_equal({ channel_id: "G0PRIVATE1", channel_name: nil },
                 @adapter.find_channel(reference: "https://acme.slack.com/archives/G0PRIVATE1/p1234567890123456"))
  end

  test "a name Slack does not list is not found, and nobody's direct messages are reachable by a user id" do
    assert_raises(AdapterError::NotFound) { @adapter.find_channel(reference: "#leadership") }
    assert_raises(AdapterError::NotFound) { @adapter.find_channel(reference: "U12345678") }
  end

  test "the post goes to the channel as Firefight's own message, its fallback saying the same as its title" do
    Slack::Client.expects(:post_message).with(
      has_entries(channel: "C0GENERAL1", text: "Message from Halon: Release 2.4 is out.")
    ).returns({ ok: true, ts: "1234567890.123456", channel: "C0GENERAL1" })

    posted = @adapter.post_channel_message(channel_id: "C0GENERAL1", message: "Release 2.4 is out.\n\nSearch is faster.",
                                           posted_by: workspace_memberships(:bob_workspace_one), by_halon: true)

    assert_equal({ message_id: "1234567890.123456", channel_id: "C0GENERAL1" }, posted)
  end

  test "Slack's refusals reach the caller as the platform neutral errors" do
    Slack::Client.stubs(:post_message).raises(AdapterError::NotInChannel.new("not_in_channel"))

    assert_raises(AdapterError::NotInChannel) do
      @adapter.post_channel_message(channel_id: "G0PRIVATE1", message: "Hi", posted_by: nil, by_halon: false)
    end
  end
end
