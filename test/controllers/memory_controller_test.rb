require "test_helper"

class MemoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @auth = catalog_entries(:auth_service)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page lists what is remembered, the instructions with their history, and what they can be about" do
    remember("Auth Service keeps sessions in Redis", subject: @auth)
    note = Chat::Instruction.create!(workspace: @workspace, scope: @auth, text: "Check logs first", added_by: @member)
    note.revise!(text: "Check metrics first", by: @member)
    handbook_page!(@workspace, "General", "In the handbook, so not listed here", by: @member)

    get memory_path, headers: inertia_headers

    assert_equal "Auth Service", inertia_props["memories"].sole["about"]
    instruction = inertia_props["instructions"].sole
    assert_equal "Check metrics first", instruction["text"]
    assert_equal [ "Check logs first" ], instruction["history"].map(&:last)
    assert_includes inertia_props["subjects"].map { |subject| subject["value"] }, "CatalogEntry:#{@auth.id}"
  end

  test "the page says how each memory stands, what Halon's nightly check found and when, and its history" do
    review = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.current, removal_cap: 3)
    checked = remember("web deploys from main")
    checked.verified_by_halon!(evidence: "The deploy settings of web name main.", review: review)
    tried = remember("Checkout runs in Frankfurt")
    tried.unsettled_by_halon!(note: "Nothing Halon reads says where Checkout runs.")
    yours = Chat::Memory.written_by!(@member, text: "Backups run nightly", subject: nil)

    get memory_path, headers: inertia_headers

    shown = inertia_props["memories"].index_by { |memory| memory["text"] }
    assert_equal [ Chat::Memory::STANDING_HALON, true, "The deploy settings of web name main.", Chat::Memory::VERDICT_RIGHT ],
                 shown["web deploys from main"].values_at("standing", "decidedByHalon", "verifiedEvidence", "checkOutcome")
    assert_equal [ Chat::Memory::STANDING_UNCHECKED, Chat::Memory::VERDICT_UNSURE, false ], shown["Checkout runs in Frankfurt"].values_at("standing", "checkOutcome", "awaitingDecision")
    assert shown["Checkout runs in Frankfurt"]["checkedAt"]
    assert_equal Chat::Memory::STANDING_PERSON, shown["Backups run nightly"]["standing"]
    assert_equal [ [ Chat::MemoryEvent::KIND_WRITTEN, Chat::MemoryEvent::ACTOR_PERSON, @member.display_name ] ],
                 shown["Backups run nightly"]["events"].map { |event| event.values_at("kind", "actor", "by") }
    assert_equal [ [ Chat::MemoryEvent::KIND_VERIFIED, "Halon", "The deploy settings of web name main." ] ],
                 shown["web deploys from main"]["events"].map { |event| event.values_at("kind", "by", "detail") }
    assert_nil shown["web deploys from main"]["confirmBlockedReason"], "a person may still confirm what only Halon checked"
    assert_equal [ checked, tried, yours ].map(&:id).sort, shown.values.map { |memory| memory["id"] }.sort
  end

  test "a person confirming what only Halon checked makes it theirs, and says so" do
    review = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.current, removal_cap: 3)
    memory = remember("web deploys from main")
    memory.verified_by_halon!(evidence: "The deploy settings of web name main.", review: review)

    post confirm_memory_path(memory)

    assert_equal "Confirmed. Halon now reads it as confirmed by you.", flash[:notice]
    assert_equal [ @member, false ], memory.reload.values_at(:confirmed_by, :decided_by_halon)
  end

  test "a person can still correct and reject what Halon checked, and each says so" do
    review = Chat::MemoryReview.create!(workspace: @workspace, reviewed_on: Date.current, removal_cap: 3)
    corrected = remember("The primary is db-1")
    corrected.verified_by_halon!(evidence: "The cluster lists db-1 as primary.", review: review)
    rejected = remember("Checkout retries twice")
    rejected.verified_by_halon!(evidence: "The client sets two retries.", review: review)

    post correct_memory_path(corrected), params: { text: "The primary is db-2", reason: "We failed over" }
    assert_equal "Corrected. Halon keeps the old wording as rejected so it does not learn it again.", flash[:notice]
    post reject_memory_path(rejected), params: { reason: "Changed last week" }
    assert_equal "Rejected. Halon stops using it and does not learn it again.", flash[:notice]

    assert_equal [ Chat::Memory::STATE_REJECTED, @member, false ], corrected.reload.values_at(:state, :rejected_by, :decided_by_halon)
    assert_equal [ Chat::Memory::STATE_REJECTED, @member ], rejected.reload.values_at(:state, :rejected_by)
    assert_equal [ Chat::MemoryEvent::KIND_VERIFIED, Chat::MemoryEvent::KIND_REJECTED ], rejected.events.map(&:kind)
  end

  test "the page redirects to the dashboard while Halon is unavailable" do
    Investigation.stubs(:available_for?).returns(false)
    Investigation.stubs(:unavailable_reason).returns("Halon is not turned on for this workspace.")

    get memory_path

    assert_redirected_to dashboard_path
  end

  test "a memory written here is confirmed by its writer and used at once" do
    post memory_memories_path, params: { text: "Deploys happen from main", subject: "CatalogEntry:#{@auth.id}" }

    memory = Chat::Memory.find_by!(workspace: @workspace, added_by: @member)
    assert_equal "Deploys happen from main", memory.text
    assert_equal Chat::Memory::STATE_CONFIRMED, memory.state
    assert_equal [ @member, @member, @auth ], [ memory.added_by, memory.confirmed_by, memory.subject ]
    assert_equal "Remembered about Auth Service. Halon uses it from now on.", flash[:notice]
  end

  test "a person confirms, corrects and rejects what Halon learned" do
    confirmed = remember("Auth Service runs on web")
    corrected = remember("Checkout reads from the replica")
    rejected = remember("Deploys happen on Fridays")

    post confirm_memory_path(confirmed)
    assert_equal Chat::Memory::STATE_CONFIRMED, confirmed.reload.state
    assert_equal @member, confirmed.confirmed_by

    post correct_memory_path(corrected), params: { text: "Checkout reads from the primary", reason: "Moved in March" }
    assert_equal Chat::Memory::STATE_REJECTED, corrected.reload.state
    assert_equal "Checkout reads from the primary", corrected.replaced_by.text

    post reject_memory_path(rejected), params: { reason: "One off" }
    assert_equal [ Chat::Memory::STATE_REJECTED, "One off" ], [ rejected.reload.state, rejected.state_reason ]
    assert_equal "Rejected. Halon stops using it and does not learn it again.", flash[:notice]
  end

  test "a decision the memory no longer allows says why, and the page ships the same reasons" do
    confirmed = remember("Auth Service runs on web")
    confirmed.confirm!(by: @member)

    post confirm_memory_path(confirmed)
    assert_equal "It is confirmed already.", flash[:alert]

    get memory_path, headers: inertia_headers
    shipped = inertia_props["memories"].sole
    assert_equal [ "It is confirmed already.", nil, true ], shipped.values_at("confirmBlockedReason", "rejectBlockedReason", "inUse")
  end

  test "a memory is deleted for good with a toast, and deleting a rejected one says its wording may be learned again" do
    used = remember("Auth Service runs on web")
    rejected = remember("Deploys happen on Fridays")
    rejected.reject!(by: @member, reason: "One off")

    delete destroy_memory_path(used)
    assert_not Chat::Memory.exists?(used.id)
    assert_equal "Deleted. Halon stops using it, and nothing keeps where it came from.", flash[:notice]

    delete destroy_memory_path(rejected)
    assert_not Chat::Memory.exists?(rejected.id)
    assert_equal "Deleted. Halon has nothing left to say the wording was wrong, so it may learn it again.", flash[:notice]
    assert_equal Chat::Memory::LEARNED_SAVED, Chat::Memory.learn!(@workspace, text: "Deploys happen on Fridays", subject: nil, source: nil).outcome
  end

  test "someone the gateway refuses memory cannot delete one, and another workspace's is not found" do
    memory = remember("Auth Service runs on web")
    elsewhere = Chat::Memory.create!(workspace: workspaces(:slack_workspace_two), text: "Theirs", state: Chat::Memory::STATE_UNCONFIRMED)

    delete destroy_memory_path(elsewhere)
    assert_response :not_found
    assert Chat::Memory.exists?(elsewhere.id)

    AbilityGateway.stubs(:permitted?).returns(false)
    delete destroy_memory_path(memory)
    assert Chat::Memory.exists?(memory.id)
  end

  test "instructions are written, edited and removed, each kept as history" do
    post memory_instructions_path, params: { text: "Check the worker logs first", subject: "CatalogEntry:#{@auth.id}" }
    note = Chat::Instruction.current.find_by!(workspace: @workspace, scope: @auth)
    assert_redirected_to memory_path(tab: MemoryController::TAB_INSTRUCTIONS)

    patch memory_instruction_path(note), params: { text: "Check the web logs first" }
    revised = Chat::Instruction.current.find_by!(workspace: @workspace, scope: @auth)
    assert_equal "Check the web logs first", revised.text

    delete memory_instruction_path(revised)
    assert_empty Chat::Instruction.current.where(workspace: @workspace)
    assert_equal 2, Chat::Instruction.where(workspace: @workspace).count
    assert_match "They are kept as history", flash[:notice]
  end

  test "a second set of instructions for the same place is refused with a reason" do
    Chat::Instruction.create!(workspace: @workspace, scope: @auth, text: "Check logs first", added_by: @member)

    post memory_instructions_path, params: { text: "Another", subject: "CatalogEntry:#{@auth.id}" }

    assert_equal "Auth Service (service) already has instructions. Edit them instead.", flash[:alert]
  end

  test "instructions for the whole workspace are written in the handbook, and a handbook page is not edited from here" do
    post memory_instructions_path, params: { text: "Never restart the primary database", subject: "" }

    assert_equal "Instructions for the whole workspace are written in the handbook.", flash[:alert]
    assert_empty Chat::Instruction.where(workspace: @workspace)

    page = handbook_page!(@workspace, "General", "Check logs first", by: @member)
    patch memory_instruction_path(page.current_wording), params: { text: "Changed from the Memory page" }

    assert_response :not_found
    assert_equal "Check logs first", page.reload.text
  end

  test "a member decides on memories without a grant, and writing instructions still needs the catalog" do
    memory = remember("Auth Service runs on web")
    sign_in(users(:bob), @workspace)

    post confirm_memory_path(memory)
    post memory_instructions_path, params: { text: "Anything" }

    assert_equal Chat::Memory::STATE_CONFIRMED, memory.reload.state
    assert_equal workspace_memberships(:bob_workspace_one), memory.confirmed_by
    assert_empty Chat::Instruction.where(workspace: @workspace)
  end

  test "someone the gateway refuses memory cannot decide on one" do
    memory = remember("Auth Service runs on web")
    AbilityGateway.stubs(:permitted?).returns(false)

    post confirm_memory_path(memory)

    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.reload.state
  end

  test "a card posted in a chat before Halon checked memories itself still settles a contradiction, and the page counts only what Halon could not settle" do
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    old = remember("web deploys from main")
    newer = Chat::Memory.create!(workspace: @workspace, text: "web deploys from release", state: Chat::Memory::STATE_UNCONFIRMED)
    old.contradicted!(newer, reason: "The deploy log of web shows \"web deploys from release\".")
    Chat::MemoryPost.create!(workspace: @workspace, conversation: conversation, kind: Chat::MemoryPost::KIND_DISPUTED, memory_ids: [ old.id ],
                             evidence: "The deploy log of web shows \"web deploys from release\".")

    get agent_chat_path(conversation), headers: chat_page_headers
    card = inertia_props[AgentChatsController::PROP_MEMORY_QUESTIONS].sole
    assert_equal [ "web deploys from main", nil ], card.values_at("remembered", "decided")

    post reject_memory_path(old), headers: { "Referer" => agent_chat_url(conversation) }

    assert_redirected_to agent_chat_url(conversation)
    assert_equal "Marked not right. Halon now remembers \"web deploys from release\" instead, confirmed by you.", flash[:notice]
    assert_equal [ Chat::Memory::STATE_CONFIRMED, @member ], newer.reload.values_at(:state, :confirmed_by)

    remember("Backups run nightly")
    frankfurt = remember("Checkout runs in Frankfurt")
    frankfurt.contradicted!(remember("Checkout runs in Dublin"), reason: "A chat showed \"Checkout runs in Dublin\".")
    frankfurt.unsettled_by_halon!(note: "Nothing Halon reads says where Checkout runs.")
    get memory_path, headers: inertia_headers
    assert_equal({ "Backups run nightly" => false, "web deploys from main" => false, "web deploys from release" => false,
                   "Checkout runs in Frankfurt" => true, "Checkout runs in Dublin" => false },
                 inertia_props["memories"].to_h { |memory| [ memory["text"], memory["awaitingDecision"] ] })
  end

  private

  def remember(text, subject: nil) = Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: Chat::Memory::STATE_UNCONFIRMED)
end
