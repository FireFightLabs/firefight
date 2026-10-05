require "test_helper"

class Slack::WorkspaceAdapter::FileOperationsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
  end

  test "a shared file is downloaded with the bot's token and handed back with its bytes" do
    Slack::Client.expects(:download_file).with(workspace: @workspace, url: "https://files.slack.com/a.log").returns({ body: "boom", content_type: "text/plain" })

    fetched = @adapter.fetch_shared_files(files: [ { "id" => "F1", "name" => "a.log", "size" => 4, "url_private_download" => "https://files.slack.com/a.log" } ], max_bytes: 10)

    assert_equal [ PlatformAdapter::SharedFile.new(name: "a.log", byte_size: 4, body: "boom", too_large: false, failure: nil) ], fetched
  end

  test "a file over the limit is never downloaded" do
    Slack::Client.expects(:download_file).never

    fetched = @adapter.fetch_shared_files(files: [ { "id" => "F1", "name" => "big.log", "size" => 11, "url_private" => "https://files.slack.com/big.log" } ], max_bytes: 10)

    assert fetched.sole.too_large
    assert_nil fetched.sole.body
  end

  test "a file Slack only names is described on request before it is downloaded" do
    Slack::Client.expects(:file_info).with(workspace: @workspace, file_id: "F1")
      .returns({ id: "F1", name: "shared.log", size: 2, url_private: "https://files.slack.com/shared.log" }.with_indifferent_access)
    Slack::Client.expects(:download_file).with(workspace: @workspace, url: "https://files.slack.com/shared.log").returns({ body: "ok", content_type: "text/plain" })

    fetched = @adapter.fetch_shared_files(files: [ { "id" => "F1", "file_access" => "check_file_info" } ], max_bytes: 10)

    assert_equal "ok", fetched.sole.body
    assert_equal "shared.log", fetched.sole.name
  end

  test "a download Slack refuses for want of files:read says how to fix it" do
    Slack::Client.expects(:download_file).raises(AdapterError, "Slack file download redirected to auth page, bot may be missing files:read scope")

    fetched = @adapter.fetch_shared_files(files: [ { "id" => "F1", "name" => "a.log", "size" => 4, "url_private" => "https://files.slack.com/a.log" } ], max_bytes: 10)

    assert_equal Slack::WorkspaceAdapter::FileOperations::NO_PERMISSION, fetched.sole.failure
    assert_nil fetched.sole.body
  end

  test "any other failure is said plainly" do
    Slack::Client.expects(:download_file).raises(AdapterError::ServerError, "500")

    fetched = @adapter.fetch_shared_files(files: [ { "id" => "F1", "name" => "a.log", "size" => 4, "url_private" => "https://files.slack.com/a.log" } ], max_bytes: 10)

    assert_equal Slack::WorkspaceAdapter::FileOperations::NOT_DOWNLOADED, fetched.sole.failure
  end
end
