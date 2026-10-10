require "test_helper"

class HandbookControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page lists the pages in order with their history, the suggestions, the roles and what Halon proposed" do
    releases = handbook_page!(@workspace, "How we release", "Tag main", by: @member)
    releases.write!(text: "Run the deploy workflow", by: @member)
    handbook_page!(@workspace, "Release guide", "x" * (Chat::HandbookPage::WHOLE_LIMIT + 1))
    Chat::HandbookProposal.propose!(Conversation.start_personal!(workspace: @workspace, member: @member), title: "What production is",
                                                                                                          text: "Production is the prod project", evidence: "Seen on the map.")

    get settings_handbook_path, headers: inertia_headers

    pages = inertia_props["pages"]
    assert_equal [ "How we release", "Release guide" ], pages.map { |page| page["title"] }
    assert_equal [ "Run the deploy workflow", [ "Tag main" ] ], [ pages.first["text"], pages.first["history"].map(&:last) ]
    assert_equal %w[whole searched], pages.map { |page| page["halonReads"] }
    assert_equal Chat::HandbookPage::SUGGESTIONS.map(&:title), inertia_props["suggestions"].map { |suggestion| suggestion["title"] }
    assert_equal "Incident Lead", inertia_props["directingRole"]
    assert_includes inertia_props["roles"].map { |role| role["name"] }, "Communications Lead"
    assert_equal "What production is", inertia_props["proposals"].sole["pageTitle"]
  end

  test "a page sets freeze windows that plans keep out of, an edit without them keeps them, and one that does not hold is refused" do
    fridays = { name: "Friday afternoons", repeat: "weekly", time_zone: "Europe/Berlin", start_day: 5, start_time: "15:00", end_day: 1, end_time: "08:00",
                lifted_by: "the CTO" }
    post handbook_pages_path, params: { title: "Freeze windows", text: "", freeze_windows: [ fridays ] }, as: :json
    page = Chat::HandbookPage.find_by!(workspace: @workspace, title: "Freeze windows")
    assert_equal "Freeze windows was added. Halon follows it from its next chat or investigation.", flash[:notice]
    assert_equal [ "Friday afternoons" ], page.freeze_rules.map(&:name)

    get settings_handbook_path(Chat::HandbookPage::PAGE_QUERY => page.id), headers: inertia_headers
    shown = inertia_props["pages"].sole["freezeWindows"].sole
    assert_equal [ "weekly", 5, "15:00", "the CTO" ], shown.values_at("repeat", "startDay", "startTime", "liftedBy")
    assert_match "Changes are frozen every Friday from 15:00 to Monday 08:00 (Europe/Berlin)", shown["sentence"]
    assert_includes inertia_props["timeZones"], "Europe/Berlin"

    patch handbook_page_path(page), params: { text: "Hotfixes still go out.", wording_id: page.current_wording.id }, as: :json
    assert_equal [ "Friday afternoons" ], page.reload.freeze_rules.map(&:name)

    patch handbook_page_path(page), params: { text: "", wording_id: page.current_wording.id, freeze_windows: [ fridays.merge(end_time: "15:00", end_day: 5) ] }, as: :json
    assert_equal [ "Friday afternoons needs to end at a different time than it starts." ], session["inertia_errors"][:base]
    assert_equal "Hotfixes still go out.", page.reload.text
  end

  test "a page is added, edited, reordered and deleted, each saying so" do
    post handbook_pages_path, params: { title: "How we release", text: "Tag main" }
    page = Chat::HandbookPage.find_by!(workspace: @workspace, title: "How we release")
    assert_equal "How we release was added. Halon follows it from its next chat or investigation.", flash[:notice]

    patch handbook_page_path(page), params: { title: "Releases", text: "Run the deploy workflow", wording_id: page.current_wording.id }
    assert_equal "Releases was updated. The earlier wording is kept as history.", flash[:notice]
    assert_equal [ "Releases", "Run the deploy workflow", 2 ], [ page.reload.title, page.text, page.wordings.count ]

    other = handbook_page!(@workspace, "Who owns what")
    patch reorder_handbook_pages_path, params: { ordered_ids: [ other.id, page.id ] }
    assert_equal "Page order updated.", flash[:notice]
    assert_equal [ other, page ], Chat::HandbookPage.where(workspace: @workspace).ordered.to_a

    delete handbook_page_path(page)
    assert_equal "Releases was deleted. Halon no longer follows it.", flash[:notice]
    assert_not Chat::HandbookPage.exists?(page.id)
  end

  test "who directs Halon is saved with the role chosen" do
    comms = incident_roles(:communications_lead_ws1)

    post handbook_pages_path, params: { title: Chat::HandbookPage::DIRECTING_TITLE, incident_role_id: comms.id, text: "" }

    assert_equal "#{Chat::HandbookPage::DIRECTING_TITLE} was added. Halon follows it from its next chat or investigation.", flash[:notice]
    assert_equal comms, Chat::HandbookPage.directing_role(@workspace)
  end

  test "a duplicate title and an edit made over someone else's are refused with why" do
    page = handbook_page!(@workspace, "How we release", "Tag main", by: @member)
    post handbook_pages_path, params: { title: "How we release", text: "Another" }
    assert_equal [ "is already the title of another page" ], session["inertia_errors"][:title]

    seen = page.current_wording.id
    page.write!(text: "Run the deploy workflow", by: @member)
    patch handbook_page_path(page), params: { text: "Stale edit", wording_id: seen }

    assert_equal [ HandbookController::CHANGED_FIRST ], session["inertia_errors"][:base]
    assert_equal "Run the deploy workflow", page.reload.text
  end

  test "a synced page cannot be edited or deleted here" do
    source = Chat::HandbookSource.create!(workspace: @workspace, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/")
    page = Chat::HandbookPage.create_written!(@workspace, title: "Deploys", text: "Run make deploy", by: nil, kind: Chat::HandbookPage::KIND_SYNCED,
                                                          source: source, source_path: "docs/deploys.md")

    patch handbook_page_path(page), params: { text: "Changed here" }
    assert_equal [ page.edit_blocked_reason ], session["inertia_errors"][:base]
    delete handbook_page_path(page)

    assert_equal "Run make deploy", page.reload.text
  end

  test "a repository folder or a document is imported, synced again and stopped, each saying so" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "Acme code")

    assert_enqueued_with(job: HandbookSyncJob) do
      post handbook_sources_path, params: { integration_id: github.id, kind: Chat::HandbookSource::KIND_REPOSITORY, repository: "acme/web", path: "docs/" }
    end
    source = Chat::HandbookSource.find_by!(workspace: @workspace, repository: "acme/web")
    assert_equal "Importing docs/ in acme/web. Its pages appear here once they are read.", flash[:notice]

    post sync_handbook_source_path(source)
    assert_equal "Syncing docs/ in acme/web now.", flash[:notice]

    delete handbook_source_path(source)
    assert_equal "Stopped syncing docs/ in acme/web. Its pages were removed.", flash[:notice]
    assert_not Chat::HandbookSource.exists?(source.id)
  end

  test "Draft with Halon starts a chat asking it to propose pages" do
    Conversation::Asking.expects(:start_personal).with { |member:, question:, **| member == @member && question == Chat::HandbookPage::DRAFT_REQUEST }
                        .returns(Conversation.start_personal!(workspace: @workspace, member: @member))

    post draft_handbook_path

    assert_match "Halon is drafting your handbook.", flash[:notice]
  end

  test "a proposal is accepted, accepted with an edit, or dismissed, each saying so" do
    page = handbook_page!(@workspace, "How we release", "Tag main", by: @member)
    accepted = propose(page: page, text: "Run the deploy workflow")
    post accept_handbook_proposal_path(accepted)
    assert_equal "How we release was updated. The earlier wording is kept as history.", flash[:notice]

    added = propose(title: "What production is", text: "Production is prod")
    post accept_handbook_proposal_path(added), params: { text: "Production is the prod project and the main database" }
    assert_equal "What production is was added with your edit. Halon follows it from its next chat or investigation.", flash[:notice]

    dismissed = propose(title: "Freeze windows", text: "No releases on Fridays")
    post dismiss_handbook_proposal_path(dismissed)
    assert_equal "The proposed new handbook page Freeze windows was dismissed. The handbook is unchanged.", flash[:notice]

    assert_equal "Run the deploy workflow", page.reload.text
    assert_equal "Production is the prod project and the main database", Chat::HandbookPage.find_by!(title: "What production is").text
    assert_not Chat::HandbookPage.exists?(title: "Freeze windows")
  end

  test "changing the handbook needs its own permission, and another workspace's proposal is not found" do
    proposal = propose(title: "Who owns what", text: "Payments owns checkout")
    elsewhere = Chat::HandbookProposal.create!(workspace: workspaces(:slack_workspace_two), title: "Theirs", text: "Theirs", evidence: "Theirs")

    post accept_handbook_proposal_path(elsewhere)
    assert_response :not_found

    sign_in(users(:bob), @workspace)
    post handbook_pages_path, params: { title: "How we release", text: "Tag main" }
    post accept_handbook_proposal_path(proposal)

    assert_not Chat::HandbookPage.exists?(workspace: @workspace, title: "How we release")
    assert proposal.reload.pending?
  end

  test "the page redirects to the dashboard while Halon is unavailable" do
    Investigation.stubs(:available_for?).returns(false)
    Investigation.stubs(:unavailable_reason).returns("Halon is not turned on for this workspace.")

    get settings_handbook_path

    assert_redirected_to dashboard_path
  end

  private

  def propose(text:, page: nil, title: nil)
    Chat::HandbookProposal.propose!(Conversation.start_personal!(workspace: @workspace, member: @member), page: page, title: title, text: text,
                                                                                                          evidence: "A fresh reading showed it.")
  end
end
