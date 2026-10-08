require "test_helper"

class Mcp::Tools::WatchesTest < ActiveSupport::TestCase
  include SlackClientStubHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    stub_post_message
    conversation = Conversation.for_mcp!(workspace: @workspace, principal: @member)
    @watch = Chat::Watch.create!(chat: conversation.chat_record, workspace: @workspace, asker: @member, title: "release run #46",
                                 expires_at: 40.minutes.from_now, limit_basis: Chat::Watch::BASIS_DEFAULT)
    @watch.steps.create!(position: 0, label: "Release run #46", capability: Integrations::Capabilities::HISTORY, arguments: {})
  end

  test "a watch started from ask_halon is listed for whoever asked, and only for them" do
    listed = Mcp::Tools::ListWatches.perform_with_principal(workspace: @workspace, principal: @member, args: {}).structured_content[:watches]

    assert_equal [ [ "release run #46", Chat::Watch::STATUS_ACTIVE, "40 min" ] ], listed.map { |watch| watch.values_at(:title, :status, :limit) }
    assert_equal "Waiting for it to start.", listed.sole[:steps].sole[:state]
    others = Mcp::Tools::ListWatches.perform_with_principal(workspace: @workspace, principal: workspace_memberships(:bob_workspace_one), args: {})
    assert_empty others.structured_content[:watches]
  end

  test "stop_watch stops it and says so, and a second stop is refused in words" do
    stopped = Mcp::Tools::StopWatch.perform_with_principal(workspace: @workspace, principal: @member, args: { watch: @watch.id })

    assert_equal Chat::Watch::STATUS_STOPPED, stopped.structured_content[:status]
    again = Mcp::Tools::StopWatch.perform_with_principal(workspace: @workspace, principal: @member, args: { watch: @watch.id })
    assert again.error?
    assert_equal Chat::Watch::NOTHING_TO_STOP, again.content.first[:text]
  end
end
