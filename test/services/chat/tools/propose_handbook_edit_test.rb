require "test_helper"

class Chat::Tools::ProposeHandbookEditTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
    @releases = handbook_page!(@workspace, "How we release", "Run the release pipeline", by: @member)
  end

  test "in a dashboard chat it proposes the edit as a card there, and the handbook stays as it is" do
    answer = nil
    assert_broadcasts(ConversationChannel.broadcasting_for(@conversation), 1) { answer = propose(@turn, page: "how we release") }

    assert_equal "Proposed. A card in this chat asks the person to accept, edit or dismiss it. Until someone accepts it, the handbook stays as it is.", answer
    proposal = @conversation.handbook_proposals.sole
    assert_equal [ @releases, "Run the deploy workflow" ], proposal.values_at(:handbook_page, :text)
    assert_equal "Run the release pipeline", @releases.reload.text
  end

  test "it proposes a new page with a title, as drafting the handbook does" do
    propose(@turn, title: "Who owns what", text: "Payments owns checkout.")

    assert_equal [ "Who owns what", nil ], @conversation.handbook_proposals.sole.values_at(:title, :handbook_page_id)
  end

  test "in an incident's thread it is posted there, and in a run in its incident's channel" do
    thread = @workspace.conversations.create!(subject: @incident, kind: Conversation::KIND_CHANNEL, channel_id: @incident.channel_id, thread_id: "1.1",
                                              started_by: @member, max_turns: 10, max_spend_cents: 50)
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    assert_enqueued_jobs(2, only: HandbookProposalPostJob) do
      assert_match "The incident's channel is asked", propose(Conversation::Turn.new(thread, asker: @member), page: "How we release")
      assert_match "Proposed.", propose(run, page: "How we release")
    end
  end

  test "it never proposes the same twice from one chat, wording the page already has, an unknown page or who directs Halon" do
    propose(@turn, page: "How we release")
    handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: incident_roles(:incident_lead_ws1))

    assert_equal "You already proposed this here, and it still waits on a person.", propose(@turn, page: "How we release")
    other_chat = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)
    assert_equal "The handbook already says that.", propose(other_chat, page: "How we release", text: "Run the release pipeline")
    assert_match "There is no handbook page called Releases.", propose(@turn, page: "Releases")
    assert_match "Halon does not propose changes to it. Nothing was proposed.", propose(@turn, page: Chat::HandbookPage::DIRECTING_TITLE, text: "Bob decides")
    assert_equal 1, Chat::HandbookProposal.where(workspace: @workspace).count
  end

  test "a run that only measures Halon is never offered it, but still searches the handbook" do
    rehearsal = @workspace.investigations.new
    rehearsal.stubs(:changes_memory?).returns(false)

    tools = Chat::Tools.memory(rehearsal).map(&:class)
    assert_not_includes tools, Chat::Tools::ProposeHandbookEdit
    assert_includes tools, Chat::Tools::SearchHandbook
  end

  private

  def propose(agent_run, page: nil, title: nil, text: "Run the deploy workflow")
    Chat::Tools::ProposeHandbookEdit.new(agent_run).call("page" => page, "title" => title, "text" => text,
                                                         "evidence" => "The last five releases ran through the deploy workflow.")
  end
end
