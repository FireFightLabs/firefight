require "test_helper"

class Slack::WorkspaceAdapter::MessagesAsTextTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
  end

  test "names the people each message mentions from the workspace's members, without asking Slack" do
    Slack::Client.expects(:list_users).never
    Slack::Client.expects(:get_user_info).never
    first = "<@#{@alice.platform_user_id}> rolled back ```v42``` :white_check_mark:"
    second = "*Thanks* <@#{@bob.platform_user_id}> &amp; <!here>"

    text = WorkspaceAdapter.for(@workspace).messages_as_text(texts: [ first, second ])

    assert_equal "@#{@alice.display_name} rolled back v42 ✅", text[first]
    assert_equal "Thanks @#{@bob.display_name} & @here", text[second]
  end

  test "a declared incident's answer carries over the question asked in Slack as Slack shows it, never notifying anyone again" do
    run = @workspace.investigations.create!(
      trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      brief: Investigation::Brief.from({ Investigation::Brief::KEY_SYMPTOM => "<!here> <@#{@bob.platform_user_id}> says it is slow &amp; :fire:" },
                                       source: Investigation::Brief::SOURCE_COMMAND)
    )
    finding = run.create_finding!(summary: "The cache did it")
    Slack::Client.expects(:post_message).with do |arguments|
      arguments[:blocks].first.dig(:text, :text).include?("into \"@here @#{@bob.display_name} says it is slow &amp; 🔥\"")
    end.returns({ "ok" => true, "ts" => "1.2", "channel" => "C1" })

    WorkspaceAdapter.for(@workspace).post_investigation_carried_over(channel_id: "C1", finding: finding)
  end

  test "the model's reading names each person from the workspace's members with their id kept" do
    Slack::Client.expects(:get_user_info).never
    message = "<@#{@alice.platform_user_id}> see <#C0123|incidents> :fire:"

    read = WorkspaceAdapter.for(@workspace).messages_for_model(texts: [ message ])

    assert_equal "@#{@alice.display_name} (#{@alice.platform_user_id}) see #incidents (C0123) 🔥", read[message]
  end

  test "a member of another workspace is not named" do
    other = workspace_memberships(:alice_workspace_two)
    message = "<@#{other.platform_user_id}> joined"

    assert_not @workspace.workspace_memberships.exists?(platform_user_id: other.platform_user_id)
    assert_equal "@someone joined", WorkspaceAdapter.for(@workspace).messages_as_text(texts: [ message ])[message]
  end
end
