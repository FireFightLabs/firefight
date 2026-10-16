require "test_helper"

module Mcp
  module Tools
    # Posting as Firefight in any channel: a change only a grant reaches, held by approval rules, in the activity log,
    # and the same tool over MCP, in Halon's chat and as a runbook step.
    class PostToChannelTest < ActiveSupport::TestCase
      CHANNELS = [ { id: "C0GENERAL1", name: "general" }, { id: "C0RELEASE1", name: "releases" } ].freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        @member = workspace_memberships(:bob_workspace_one)
        stub_list_conversations(channels: CHANNELS)
        stub_get_permalink(permalink: "https://acme.slack.com/archives/C0GENERAL1/p1234567890123456")
      end

      def call(principal, args) = ToolDispatcher.call(tool: PostToChannel, server_context: { workspace: @workspace, principal: principal }, args: args)

      def text_of(response) = response.content.first[:text]

      test "an admin posts by the channel's name, and the activity log holds the call with what was posted" do
        Slack::Client.expects(:post_message).with(has_entries(channel: "C0GENERAL1")).returns({ ok: true, ts: "1234567890.123456", channel: "C0GENERAL1" })

        answer = call(@admin, { channel: "#general", message: "Release 2.4 is out." })

        assert_not answer.error?
        assert_equal [ true, "#general", "C0GENERAL1", "https://acme.slack.com/archives/C0GENERAL1/p1234567890123456" ],
                     answer.structured_content.values_at(:posted, :channel, :channel_id, :link)
        row = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::CHANNEL_POST, principal: @admin)
        assert_equal [ Ability::Invocation::DECISION_ALLOW, Ability::Invocation::OUTCOME_SUCCESS ], [ row.decision, row.outcome ]
        assert_equal [ "#general", "Release 2.4 is out." ], row.params.values_at("channel", "message")
      end

      test "a member needs a grant, and with one the post goes through" do
        Slack::Client.expects(:post_message).never
        denied = call(@member, { channel: "general", message: "Hello" })
        assert denied.error?
        assert_match "channel_posts:create", text_of(denied)
        assert Ability::Invocation.exists?(workspace: @workspace, action_key: Ability::Action::CHANNEL_POST, principal: @member, decision: Ability::Invocation::DECISION_DENY)

        Ability::Grant.grant!(workspace: @workspace, principal: @member, target: { action: Ability::Action.system!(Ability::Action::CHANNEL_POST) })
        Slack::Client.unstub(:post_message)
        stub_post_message

        assert_not call(@member, { channel: "general", message: "Hello" }).error?
      end

      test "an agent holds nothing without an explicit grant, whatever its creator can do" do
        agent = @workspace.agents.create!(name: "Release bot", slug: "release_bot")
        Slack::Client.expects(:post_message).never

        assert call(agent, { channel: "general", message: "Shipped" }).error?
        assert_not agent.permitted_to?(Ability::Action.system!(Ability::Action::CHANNEL_POST), @workspace)
      end

      test "an approval rule holds the post until it is approved, and nothing is posted meanwhile" do
        @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
        Slack::Client.expects(:post_message).never

        held = call(@admin, { channel: "general", message: "Maintenance tonight at 22:00" })

        assert held.error?
        assert_match "Approval required", text_of(held)
        approval = @workspace.ability_approvals.find_by!(action_key: Ability::Action::CHANNEL_POST)
        assert_equal "general", approval.params["channel"]
      end

      test "the post is drawn as Firefight's, with the message escaped so it can never ping the channel" do
        posted = nil
        Slack::Client.expects(:post_message).with { |payload| posted = payload }.returns({ ok: true, ts: "1.2", channel: "C0GENERAL1" })

        grant_post(@member)
        call(@member, { channel: "general", message: "Release notes <!channel>\n\n- Faster search\n- [Changelog](https://example.com/changes)" })

        blocks = posted[:blocks]
        assert_equal ":mega:  *Message from Firefight*", blocks.first.dig(:text, :text)
        assert_equal "divider", blocks.second[:type]
        body = blocks[2].dig(:text, :text)
        assert_includes body, "> Release notes &lt;!channel&gt;"
        assert_includes body, "> • Faster search"
        assert_includes body, "<https://example.com/changes|Changelog>"
        assert_equal "Posted through Firefight by <@U87654321>", blocks.last.dig(:elements, 0, :text)
        assert_equal "Message from Firefight: Release notes &lt;!channel&gt;", posted[:text]
      end

      test "a channel Firefight cannot see is refused with what to do, and the activity log says it failed" do
        Slack::Client.expects(:post_message).never

        refused = call(@admin, { channel: "#leadership", message: "Hello" })

        assert refused.error?
        assert_equal "Firefight cannot see #leadership. Check the name. If it is a private channel, invite Firefight to it, then name it by its link.", text_of(refused)
        row = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::CHANNEL_POST)
        assert_equal Ability::Invocation::OUTCOME_ERROR, row.outcome
      end

      test "a private channel Firefight is not in is refused with inviting Firefight, named by its link or its id" do
        stub_post_message(raises: AdapterError::NotFound.new("channel_not_found"))
        by_link = call(@admin, { channel: "https://acme.slack.com/archives/G0PRIVATE1", message: "Hello" })
        assert_match "invite Firefight to it", text_of(by_link)

        Slack::Client.unstub(:post_message)
        stub_post_message(raises: AdapterError::NotInChannel.new("not_in_channel"))
        by_id = call(@admin, { channel: "G0PRIVATE1", message: "Hello" })
        assert_equal "Firefight is not in that channel, so it cannot post there. Invite Firefight to the channel, then ask again.", text_of(by_id)
      end

      test "an archived channel, an empty message and one that is too long are refused before anything reaches Slack" do
        stub_post_message(raises: AdapterError::IsArchived.new("is_archived"))
        assert_equal "#general is archived, so nothing can be posted there.", text_of(call(@admin, { channel: "general", message: "Hi" }))

        Slack::Client.unstub(:post_message)
        Slack::Client.expects(:post_message).never
        assert_equal "Say what to post.", text_of(call(@admin, { channel: "general", message: "  " }))
        assert_match "longer than 10,000 characters", text_of(call(@admin, { channel: "general", message: "a" * 10_001 }))
      end

      test "Halon's chat offers it to whoever holds the grant, asks the person first, and the post names Halon and who asked" do
        conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
        entry = -> { Chat::Tools.catalog(Conversation::Turn.new(conversation, asker: @member)).find { |each| each.name.to_s == POST_TO_CHANNEL } }
        assert_equal Chat::Tools::STATE_NOT_GRANTED, entry.call.state
        assert_equal Chat::Tools::Groups::CHANNELS, entry.call.group

        grant_post(@member)
        tool = entry.call.tool
        assert tool.requires_approval?

        posted = nil
        Slack::Client.expects(:post_message).with { |payload| posted = payload }.returns({ ok: true, ts: "1.2", channel: "C0RELEASE1" })
        said = tool.call(channel: "<#C0RELEASE1|releases>", message: "The 2.4 release notes are in the changelog.")

        assert_match "\"posted\": true", said
        assert_equal ":mega:  *Message from Halon*", posted[:blocks].first.dig(:text, :text)
        assert_equal "Posted by Halon at the request of <@U87654321>", posted[:blocks].last.dig(:elements, 0, :text)
        row = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Action::CHANNEL_POST, principal: @member)
        assert_equal AbilityGateway::SOURCE_CONVERSATION, row.source
      end

      test "it is offered in the editor with its channel and message" do
        choice = Chat::Tools::Choices.tools(@workspace).find { |each| each.name == POST_TO_CHANNEL }
        assert_equal "Posting in channels", choice.group
        assert_equal [ [ "channel", true ], [ "message", true ], [ "approval_id", false ] ], choice.fields.map { |field| [ field.key, field.required ] }
      end

      private

      def grant_post(principal)
        Ability::Grant.grant!(workspace: @workspace, principal: principal, target: { action: Ability::Action.system!(Ability::Action::CHANNEL_POST) })
      end
    end
  end
end
