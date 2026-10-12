require "test_helper"

class Slack::WorkspaceAdapter::MessagesAsMarkdownTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "names the people each message mentions from the workspace's members, without asking Slack" do
    Slack::Client.expects(:list_users).never
    Slack::Client.expects(:get_user_info).never
    first = "<@#{@alice.platform_user_id}> rolled back ```v42```"
    second = "*Thanks* <@#{@bob.platform_user_id}>"

    markdown = WorkspaceAdapter.for(@workspace).messages_as_markdown(texts: [ first, second ])

    assert_equal "@#{@alice.display_name} rolled back \n```\nv42\n```", markdown[first]
    assert_equal "**Thanks** @#{@bob.display_name}", markdown[second]
  end

  test "standard emoji read as themselves, and the workspace's own and any in code stay as typed" do
    text = ":white_check_mark: rolled back :+1::skin-tone-3: :partyparrot: `:rocket:`"

    markdown = WorkspaceAdapter.for(@workspace).messages_as_markdown(texts: [ text ])

    assert_equal "✅ rolled back 👍🏼 :partyparrot: `:rocket:`", markdown[text]
  end

  test "a member of another workspace is not named" do
    other = workspace_memberships(:alice_workspace_two)
    text = "<@#{other.platform_user_id}> joined"

    assert_not @workspace.workspace_memberships.exists?(platform_user_id: other.platform_user_id)
    assert_equal "@someone joined", WorkspaceAdapter.for(@workspace).messages_as_markdown(texts: [ text ])[text]
  end
end
