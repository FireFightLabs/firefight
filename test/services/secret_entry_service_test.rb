require "test_helper"

# A secret a chat in a Slack thread handed to a person is pointed to from the thread, and never typed there.
class SecretEntryServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @set_secret = github.tools.create!(name: "set_actions_secret", read_only: false, enabled: true)
    @conversation = @workspace.conversations.create!(kind: Conversation::KIND_CHANNEL, started_by: @bob, channel_id: "C9", thread_id: "5.5",
                                                     max_turns: 5, max_spend_cents: 100)
    @entry = @conversation.chat_record.secret_entries.create!(
      kind: Chat::SecretEntry::KIND_ENTER, status: Chat::SecretEntry::STATUS_PENDING, tool: @set_secret, requester: @bob,
      title: "DEPLOY_HOOK in acme/web", target: { "repo" => "acme/web", "name" => "DEPLOY_HOOK" }, expires_at: 1.hour.from_now
    )
    @adapter = stub
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("APP_HOST").returns("app.firefight.test")
  end

  test "the thread gets a message linking to the chat, with no field of its own, redrawn once the value is set" do
    @adapter.expects(:post_secret_entry).with do |channel_id:, thread_id:, entry:|
      blocks = Slack::Messages::SecretEntry.build(entry)
      channel_id == "C9" && thread_id == "5.5" &&
        blocks.to_json.include?("Bob Jones types the value in this chat in Firefight, so it never passes through Slack or Halon.") &&
        blocks.last[:elements].sole[:url].end_with?("/agent/#{@conversation.id}") && blocks.none? { |block| block[:type] == "input" }
    end.returns(channel_id: "C9", message_id: "5.6")
    SecretEntryService.recorded!(@entry)
    assert_equal "5.6", @entry.reload.message_id

    Integrations::Packs::Github.any_instance.stubs(:fill_secret).returns("Set DEPLOY_HOOK in acme/web.")
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: @set_secret.reload.ability_action)
    @adapter.expects(:update_secret_entry).with do |entry:, **|
      blocks = Slack::Messages::SecretEntry.build(entry)
      blocks.to_json.include?("Set by Bob Jones at") && blocks.none? { |block| block[:type] == "actions" }
    end.returns(success: true)

    assert SecretEntryService.fill!(@entry, value: "s3cret", by: @bob).ok
  end

  test "only the person the call ran as can fill it, and two submissions never both send" do
    alice = workspace_memberships(:alice_workspace_one)
    assert_equal "Only Bob Jones can enter this value, since the change runs as them.", SecretEntryService.fill!(@entry, value: "x", by: alice).words

    assert @entry.claim!
    refute Chat::SecretEntry.find(@entry.id).claim!
    @entry.released!
    assert_equal Chat::SecretEntry::STATUS_PENDING, @entry.status
  end
end
