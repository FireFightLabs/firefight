require "test_helper"

# What the handbook page costs the database. Each pending proposal shows the wording its page holds now and whether the
# page changed since, so more proposals must not mean more queries.
class HandbookQueriesTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "the page costs the same for many pending proposals as for a few" do
    proposals(2)
    get settings_handbook_path, headers: inertia_headers
    few = queries_sent { get settings_handbook_path, headers: inertia_headers }
    proposals(10)
    many = queries_sent { get settings_handbook_path, headers: inertia_headers }

    assert_response :success
    assert_same_queries few, many
  end

  test "each proposal says whether its page changed or its title was taken since, as before" do
    changed, current, taken, free = proposals(1).flatten
    changed.handbook_page.write!(text: "Someone else's words", by: @member)
    handbook_page!(@workspace, taken.title)

    get settings_handbook_path, headers: inertia_headers

    shown = inertia_props["proposals"].index_by { |proposal| proposal["id"] }
    assert_equal [ changed, current, taken, free ].map(&:accept_blocked_reason), [ changed, current, taken, free ].map { |proposal| shown[proposal.id]["acceptBlockedReason"] }
    assert_equal [ true, false, true, false ], [ changed, current, taken, free ].map { |proposal| shown[proposal.id]["acceptBlockedReason"].present? }
    assert_equal "Someone else's words", shown[changed.id]["currentWording"]
  end

  private

  # Each round proposes an edit to two pages and two new pages.
  def proposals(rounds)
    Array.new(rounds) do
      pages = Array.new(2) { handbook_page!(@workspace, "Page #{SecureRandom.hex(3)}", "Old words", by: @member) }
      edits = pages.map { |page| Chat::HandbookProposal.propose!(@conversation, page: page, text: "New words", evidence: "Read it") }
      added = Array.new(2) { Chat::HandbookProposal.propose!(@conversation, title: "New #{SecureRandom.hex(3)}", text: "Words", evidence: "Read it") }
      edits + added
    end
  end
end
