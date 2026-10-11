require "test_helper"

class Chat::ScreenshotTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  JPEG = "\xFF\xD8\xFF\xE0fake-jpeg".b.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @owner = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @owner)
    @chat = @conversation.chat_record
  end

  test "each screen size's picture is kept encrypted, and one that is not a JPEG is left out without failing the check" do
    kept = Chat::Screenshot.record!(@chat, [ viewport("desktop"), viewport("phone", screenshot: Base64.strict_encode64("<svg/>")) ], tool_call_id: "call_1")

    assert_equal [ "desktop" ], kept.map(&:viewport)
    shot = kept.first
    assert_equal JPEG, shot.bytes
    assert_not_equal JPEG, shot.sealed.download, "the object store holds the bytes encrypted"
    assert_equal "Desktop: Cart at https://shop.example.com/cart", shot.caption
  end

  test "a stop before a send is found for the same check while it is fresh, and however old for a confirmation drawn later" do
    stopped = viewport("desktop", stopped: { "step" => 2, "reason" => "sends_data", "would_send" => { "method" => "POST", "url" => "https://shop.example.com/orders" } })
    shot = Chat::Screenshot.record!(@chat, [ stopped ], digest: "abc").first

    assert_equal shot, Chat::Screenshot.stopped_before(@chat, "abc", 2)
    assert_nil Chat::Screenshot.stopped_before(@chat, "other", 2)
    assert_equal [ [ "Sends", "POST https://shop.example.com/orders" ] ], shot.would_send_rows

    travel Chat::Screenshot::SEND_FRESH_FOR + 1.minute do
      assert_nil Chat::Screenshot.stopped_before(@chat, "abc", 2)
      assert_equal shot, Chat::Screenshot.stopped_before(@chat, "abc", 2, fresh: false)
    end
  end

  test "only whoever may read the chat may see what its browser saw, and the pictures go with the chat" do
    shot = Chat::Screenshot.record!(@chat, [ viewport("desktop") ]).first

    assert shot.readable_by?(@owner)
    assert_not shot.readable_by?(workspace_memberships(:bob_workspace_one))
    assert_not shot.readable_by?(nil)

    blob = shot.sealed.blob
    perform_enqueued_jobs { @chat.destroy! }
    assert_not Chat::Screenshot.exists?(shot.id)
    assert_not ActiveStorage::Blob.exists?(blob.id), "the bytes leave the object store with the chat"
  end

  private

  def viewport(name, screenshot: Base64.strict_encode64(JPEG), stopped: nil)
    { "name" => name, "final_url" => "https://shop.example.com/cart", "title" => "Cart", "screenshot" => screenshot, "stopped" => stopped }
  end
end
