require "test_helper"

class Interactions::HandbookProposalHandlersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    @releases = handbook_page!(@workspace, "How we release", "Run the release pipeline")
    @thread = @workspace.conversations.create!(subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id, thread_id: "1.1",
                                               started_by: @member, max_turns: 10, max_spend_cents: 50)
    @adapter = @workspace.adapter
    Workspace.any_instance.stubs(:adapter).returns(@adapter)
    @proposal = Chat::HandbookProposal.propose!(@thread, page: @releases, text: "Run the deploy workflow",
                                                         evidence: "The last five releases ran through the deploy workflow.")
  end

  test "it is posted in the thread its chat speaks in, and the message is kept so a decision redraws it" do
    @adapter.expects(:post_handbook_proposal).with { |channel_id:, thread_id:, proposal:|
      channel_id == @incident.channel_id && thread_id == "1.1" && proposal.text == "Run the deploy workflow" && proposal.current_wording == "Run the release pipeline"
    }.returns(message_id: "2.2", channel_id: @incident.channel_id)

    HandbookProposalPostJob.perform_now(@proposal.id)

    assert_equal [ @incident.channel_id, "1.1", "2.2" ], @proposal.reload.values_at(:channel_id, :thread_id, :message_id)
  end

  test "Accept writes the proposed wording as whoever pressed it and redraws the message saying so" do
    @proposal.update!(channel_id: @incident.channel_id, message_id: "2.2")
    @adapter.expects(:update_handbook_proposal).with { |message_id:, proposal:, **| message_id == "2.2" && proposal.decided == "Accepted by #{@member.display_name}." }

    assert_nil Interactions::HandbookProposalDecisionHandler.execute(click(Identifiers::HANDBOOK_PROPOSAL_ACCEPT))

    assert_equal "Run the deploy workflow", @releases.reload.text
  end

  test "Dismiss keeps the handbook, and pressing again tells only the presser how it was settled" do
    @adapter.stubs(:update_handbook_proposal)
    Interactions::HandbookProposalDecisionHandler.execute(click(Identifiers::HANDBOOK_PROPOSAL_DISMISS))
    @adapter.expects(:post_ephemeral).with(channel_id: @incident.channel_id, user_id: @member.platform_user_id, text: "Dismissed by #{@member.display_name}.")

    Interactions::HandbookProposalDecisionHandler.execute(click(Identifiers::HANDBOOK_PROPOSAL_ACCEPT))

    assert_equal "Run the release pipeline", @releases.reload.text
    assert_equal 1, @releases.wordings.count
  end

  test "Edit opens the form holding the proposed wording, and its submission accepts the person's wording" do
    @adapter.expects(:open_handbook_proposal_modal).with { |trigger_id:, proposal:| trigger_id == "T1" && proposal.text == "Run the deploy workflow" }
    Interactions::OpenHandbookProposalEditHandler.execute(click(Identifiers::HANDBOOK_PROPOSAL_EDIT, trigger_id: "T1"))

    @adapter.stubs(:update_handbook_proposal)
    assert_nil Interactions::EditHandbookProposalHandler.execute(submission("Run the deploy workflow, then check checkout"))

    assert_equal "Run the deploy workflow, then check checkout", @releases.reload.text
    assert @proposal.reload.edited
  end

  test "an empty edit, or one of a page someone changed since, keeps the form open with why" do
    assert_equal "Write what the handbook should say.", error_of(Interactions::EditHandbookProposalHandler.execute(submission("")))

    @releases.write!(text: "Run the release pipeline from main", by: @member)
    assert_match "Someone changed How we release since Halon proposed this.", error_of(Interactions::EditHandbookProposalHandler.execute(submission("Anything")))
    assert @proposal.reload.pending?
  end

  test "deciding needs the permission writing the handbook needs, and opening the form is a read" do
    [ Interactions::HandbookProposalDecisionHandler, Interactions::EditHandbookProposalHandler ].each do |handler|
      assert_equal [ Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_UPDATE ], handler.authorization
    end
    assert_equal [ Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_READ ], Interactions::OpenHandbookProposalEditHandler.authorization
  end

  private

  def click(action_id, trigger_id: nil)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, trigger_id: trigger_id,
                    channel_id: @incident.channel_id, message_id: "2.2", user_id: @member.platform_user_id,
                    action_id: action_id, action_value: @proposal.id)
  end

  def submission(text)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @member.platform_user_id,
                    callback_id: Identifiers::HANDBOOK_PROPOSAL_EDIT_MODAL,
                    private_metadata: ModalState.encode(handbook_proposal_id: @proposal.id),
                    values: { Slack::Modals::EditHandbookProposal::TEXT_BLOCK => { Slack::Modals::EditHandbookProposal::TEXT_INPUT => { "value" => text } } })
  end

  def error_of(response) = response[:errors][Slack::Modals::EditHandbookProposal::TEXT_BLOCK]
end
