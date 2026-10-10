require "test_helper"

class Chat::HandbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @lead = incident_roles(:incident_lead_ws1)
    @comms = incident_roles(:communications_lead_ws1)
  end

  test "pages keep their order, and an edit keeps the earlier wording as history" do
    releases = handbook_page!(@workspace, "How we release", "Tag main, then run the release pipeline", by: @member)
    owners = handbook_page!(@workspace, "Who owns what", "Payments owns checkout", by: @member)

    releases.write!(text: "Run the deploy workflow", by: @member)

    assert_equal [ releases, owners ], Chat::HandbookPage.where(workspace: @workspace).ordered.to_a
    assert_equal "Run the deploy workflow", releases.reload.text
    assert_equal [ "Tag main, then run the release pipeline", "Run the deploy workflow" ], releases.wordings.map(&:text)
  end

  test "an edit made over someone else's is refused and theirs is kept" do
    page = handbook_page!(@workspace, "How we release", "Tag main", by: @member)
    seen = page.current_wording.id
    page.write!(text: "Run the deploy workflow", by: @member)

    assert_nil page.write!(text: "Stale edit", by: @member, wording_id: seen)
    assert_equal "Run the deploy workflow", page.reload.text
  end

  test "titles are unique in a workspace, and a page is long enough for a real document" do
    handbook_page!(@workspace, "How we release")
    duplicate = Chat::HandbookPage.new(workspace: @workspace, title: "how WE release", kind: Chat::HandbookPage::KIND_WRITTEN)

    assert_includes duplicate.tap(&:valid?).errors.full_messages, "Title is already the title of another page"
    long = handbook_page!(@workspace, "Release guide", "word " * 20_000)
    assert_operator long.text.length, :>, 90_000
  end

  test "the whole workspace's instructions are always on a page" do
    nowhere = Chat::Instruction.new(workspace: @workspace, text: "Never restart the database")

    assert_equal [ Chat::Instruction::WHOLE_WORKSPACE_ELSEWHERE ], nowhere.tap(&:valid?).errors.full_messages
  end

  test "Halon takes direction from the Incident Lead until the handbook names another role, and again once that role is disabled" do
    assert_equal @lead, Chat::HandbookPage.directing_role(@workspace)

    page = handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: @comms)
    assert_equal @comms, Chat::HandbookPage.directing_role(@workspace)
    assert_equal "Halon takes direction from whoever holds Communications Lead.", page.halon_text

    @comms.update!(deleted_at: Time.current)
    assert_equal @lead, Chat::HandbookPage.directing_role(@workspace)
    assert page.reload.current_wording.role_set_aside?
  end

  test "the handbook holds one page saying who directs Halon, and it names a role of this workspace" do
    handbook_page!(@workspace, Chat::HandbookPage::DIRECTING_TITLE, "", role: @comms)
    second = Chat::HandbookPage.new(workspace: @workspace, title: "Who decides", kind: Chat::HandbookPage::KIND_DIRECTING)
    elsewhere = Chat::Instruction.new(workspace: @workspace, handbook_page: Chat::HandbookPage.find_by!(kind: Chat::HandbookPage::KIND_DIRECTING),
                                      incident_role: incident_roles(:incident_commander_ws2))
    stray = Chat::Instruction.new(workspace: @workspace, handbook_page: handbook_page!(@workspace, "Releases"), incident_role: @lead, text: "Tag main")

    assert_includes second.tap(&:valid?).errors.full_messages, "The handbook already has a page saying who directs Halon. Edit that one instead."
    assert_includes elsewhere.tap(&:valid?).errors.full_messages, "That role is not in this workspace."
    assert_not stray.valid?
  end

  test "Halon is given short pages whole in order, and only names a long page and pages past the budget for search" do
    short = handbook_page!(@workspace, "How we release", "Tag main.")
    long = handbook_page!(@workspace, "Release guide", "x" * (Chat::HandbookPage::WHOLE_LIMIT + 1))

    read = Chat::HandbookPage.for_halon(@workspace)
    lines = Chat::HandbookPage.halon_lines(@workspace)

    assert_equal [ short ], read.whole
    assert_equal [ long ], read.searched
    assert_equal "Page \"How we release\" (#{short.url}):\nTag main.", lines.first
    assert_equal "Pages too long to give here, which search_handbook reads: \"Release guide\" (#{long.url})", lines.last
  end

  test "pages together never pass the budget Halon is given" do
    pages = 7.times.map { |index| handbook_page!(@workspace, "Page #{index}", "y" * Chat::HandbookPage::WHOLE_LIMIT) }

    read = Chat::HandbookPage.for_halon(@workspace)

    assert_equal pages.first(6), read.whole
    assert_equal [ pages.last ], read.searched
  end

  test "a synced page is changed only at its source" do
    source = Chat::HandbookSource.create!(workspace: @workspace, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/")
    page = Chat::HandbookPage.create_written!(@workspace, title: "Deploys", text: "Run make deploy", by: nil, kind: Chat::HandbookPage::KIND_SYNCED,
                                                          source: source, source_path: "docs/deploys.md")

    assert_equal "Deploys is synced from docs/ in acme/web. Change it there, or stop syncing it.", page.edit_blocked_reason
    assert_equal page.edit_blocked_reason, page.delete_blocked_reason
    assert_equal page.edit_blocked_reason, page.proposal_blocked_reason
  end
end
