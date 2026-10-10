require "test_helper"

class Chat::HandbookProposalTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @other = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @releases = handbook_page!(@workspace, "How we release", "Run the release pipeline", by: @member)
  end

  test "accepting writes the proposed wording and keeps the old one as history" do
    proposal = propose

    written = proposal.accept!(by: @other)

    assert_equal "Run the deploy workflow", @releases.reload.text
    assert_equal @other, written.added_by
    assert_equal [ Chat::HandbookProposal::STATUS_ACCEPTED, @other, false, written ], proposal.reload.values_at(:status, :decided_by, :edited, :result)
    assert_equal "Accepted by #{@other.display_name}.", proposal.decided_sentence
  end

  test "accepting with an edit writes the person's wording and says so" do
    proposal = propose

    proposal.accept!(by: @other, text: "Run the deploy workflow, then check checkout")

    assert_equal "Run the deploy workflow, then check checkout", @releases.reload.text
    assert_equal "Accepted with an edit by #{@other.display_name}.", proposal.reload.decided_sentence
  end

  test "a new page Halon drafted is added when accepted" do
    proposal = Chat::HandbookProposal.propose!(@conversation, title: "Who owns what", text: "Payments owns checkout.", evidence: "The catalogue says so.")

    page = proposal.accept!(by: @member).handbook_page

    assert_equal [ "Who owns what", "Payments owns checkout." ], [ page.title, page.text ]
    assert_equal "#{@member.display_name} accepted your proposed new handbook page Who owns what. Follow the handbook as it now reads.",
                 proposal.reload.outcome_note
  end

  test "two people pressing at once leave one decision, and the second is told how it was settled" do
    proposal = propose
    stale = Chat::HandbookProposal.find(proposal.id)

    assert proposal.dismiss!(by: @member)
    assert_nil stale.accept!(by: @other)
    assert_equal "Run the release pipeline", @releases.reload.text
    assert_equal "Dismissed by #{@member.display_name}.", stale.accept_blocked_reason
  end

  test "a proposal made before someone changed the page cannot be accepted, and the page keeps their change" do
    proposal = propose
    @releases.write!(text: "Run the release pipeline from main only", by: @other)

    assert_equal "Someone changed How we release since Halon proposed this. Read the handbook again before deciding.", proposal.accept_blocked_reason
    assert_nil proposal.accept!(by: @member)
    assert proposal.reload.pending?
    assert_nil proposal.dismiss_blocked_reason
  end

  test "a new page whose title was taken since cannot be accepted" do
    proposal = Chat::HandbookProposal.propose!(@conversation, title: "Freeze windows", text: "No Friday releases.", evidence: "Seen in CI.")
    handbook_page!(@workspace, "Freeze windows", "Fridays are quiet.")

    assert_equal "A page called Freeze windows was added since Halon proposed it. Read the handbook again before deciding.", proposal.accept_blocked_reason
  end

  test "a chat is told each decision once" do
    propose.accept!(by: @other)

    notes = Chat::HandbookProposal.untold_for!(@conversation).map(&:outcome_note)

    assert_equal [ "#{@other.display_name} accepted your proposed edit to the handbook page How we release. Follow the handbook as it now reads." ], notes
    assert_empty Chat::HandbookProposal.untold_for!(@conversation)
  end

  test "a synced page, who directs Halon and wording that looks like a secret are never proposed" do
    directing = handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: incident_roles(:incident_lead_ws1))
    secret = Chat::HandbookProposal.new(workspace: @workspace, title: "Production", text: "Use postgres://app:hunter2@db/prod", evidence: "Read it")

    error = assert_raises(ActiveRecord::RecordInvalid) { Chat::HandbookProposal.propose!(@conversation, page: directing, text: "Bob decides", evidence: "Said so") }
    assert_match "Halon does not propose changes to it", error.message
    assert_match "looks like it holds a secret", secret.tap(&:valid?).errors.full_messages.to_sentence
  end

  private

  def propose
    Chat::HandbookProposal.propose!(@conversation, page: @releases, text: "Run the deploy workflow", evidence: "The last five releases ran through the deploy workflow.")
  end
end
