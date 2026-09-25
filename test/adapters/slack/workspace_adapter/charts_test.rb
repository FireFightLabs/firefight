require "test_helper"

class Slack::WorkspaceAdapter::ChartsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
    @chart = Chat::Chart::Post.new(
      title: "5xx responses of <web>", summary: "web-1: max 42 at 14:05", link: "https://app.northflank.com/t/acme/project/p/services/web", png: "PNG".b
    )
  end

  test "a chart is uploaded into the thread with its numbers and a link to the live chart" do
    Slack::Client.expects(:upload_file).with do |arguments|
      arguments[:channel] == "C1" && arguments[:thread_ts] == "1.2" && arguments[:content] == "PNG".b &&
        arguments[:filename] == "5xx-responses-of-web.png" &&
        arguments[:comment] == "*5xx responses of &lt;web&gt;*\nweb-1: max 42 at 14:05\n<https://app.northflank.com/t/acme/project/p/services/web|Open the live chart>"
    end.returns({ ok: true })

    @adapter.post_charts(channel_id: "C1", thread_id: "1.2", charts: [ @chart ])
  end

  test "a workspace that has not granted file uploads gets the numbers and the link as a message" do
    Slack::Client.stubs(:upload_file).raises(AdapterError::MissingPermission, "missing_scope")
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:thread_ts] == "1.2" && arguments[:text].include?("web-1: max 42") && arguments[:text].include?("Open the live chart")
    end.returns({ ok: true, ts: "1.3" })

    posted = @adapter.post_charts(channel_id: "C1", thread_id: "1.2", charts: [ @chart ])

    assert_equal [ { message_id: "1.3", channel_id: "C1" } ], posted
  end

  test "Slack's missing scope answer is read as a missing permission" do
    assert_kind_of AdapterError::MissingPermission, Slack::Client.typed_error_for("missing_scope", { error: "missing_scope", needed: "files:write" })
  end
end
