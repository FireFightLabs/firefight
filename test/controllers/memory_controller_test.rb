require "test_helper"

class MemoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @auth = catalog_entries(:auth_service)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the page lists what is remembered, the instructions with their history, and what they can be about" do
    remember("Auth Service keeps sessions in Redis", subject: @auth)
    note = Chat::Instruction.create!(workspace: @workspace, text: "Check logs first", added_by: @member)
    note.revise!(text: "Check metrics first", by: @member)

    get memory_path, headers: inertia_headers

    assert_equal "Auth Service", inertia_props["memories"].sole["about"]
    instruction = inertia_props["instructions"].sole
    assert_equal "Check metrics first", instruction["text"]
    assert_equal [ "Check logs first" ], instruction["history"].map(&:last)
    assert_includes inertia_props["subjects"].map { |subject| subject["value"] }, "CatalogEntry:#{@auth.id}"
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
    Chat::Instruction.create!(workspace: @workspace, text: "Check logs first", added_by: @member)

    post memory_instructions_path, params: { text: "Another", subject: "" }

    assert_equal "Whole workspace already has instructions. Edit them instead.", flash[:alert]
  end

  test "a member who cannot manage the catalog reads the page and changes nothing" do
    memory = remember("Auth Service runs on web")
    sign_in(users(:bob), @workspace)

    get memory_path, headers: inertia_headers
    assert_response :success

    post confirm_memory_path(memory)
    post memory_instructions_path, params: { text: "Anything" }

    assert_equal Chat::Memory::STATE_UNCONFIRMED, memory.reload.state
    assert_empty Chat::Instruction.where(workspace: @workspace)
  end

  private

  def remember(text, subject: nil) = Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: Chat::Memory::STATE_UNCONFIRMED)
end
