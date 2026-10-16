require "test_helper"

class Slack::WorkspaceAdapter::ScreenshotsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
    @shot = Chat::Screenshot::Post.new(caption: "Desktop: Cart <b> at https://shop.example.com/cart", filename: "desktop-1.jpg", jpeg: "JPEG".b)
  end

  test "a page the browser saw is uploaded into the thread with its caption escaped, and the ones left out are counted" do
    Slack::Client.expects(:upload_file).with do |arguments|
      arguments[:channel] == "C1" && arguments[:thread_ts] == "1.2" && arguments[:content] == "JPEG".b && arguments[:filename] == "desktop-1.jpg" &&
        arguments[:comment] == "_Desktop: Cart &lt;b&gt; at https://shop.example.com/cart_"
    end.returns({ ok: true })
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text].include?("2 more screenshots") }.returns({ ok: true, ts: "1.4" })

    @adapter.post_screenshots(channel_id: "C1", thread_id: "1.2", screenshots: [ @shot ], left_out: 2)
  end

  test "a workspace that has not granted file uploads gets the caption as a message" do
    Slack::Client.stubs(:upload_file).raises(AdapterError::MissingPermission, "missing_scope")
    Slack::Client.expects(:post_message).with { |arguments| arguments[:text].include?("Desktop: Cart") }.returns({ ok: true, ts: "1.3" })

    assert_equal [ { message_id: "1.3", channel_id: "C1" } ], @adapter.post_screenshots(channel_id: "C1", thread_id: "1.2", screenshots: [ @shot ])
  end
end
