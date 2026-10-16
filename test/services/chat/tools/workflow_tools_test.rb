require "test_helper"

# Halon reads a workflow and proposes changes to it, from a chat beside its canvas or naming it anywhere else.
class Chat::Tools::WorkflowToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Release check")
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => step("wait") }, by: @member)
    @workflow.reload.draft.publish!(by: @member)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member, subject: @workflow.reload)
    @turn = Conversation::Turn.new(@conversation, asker: @member)
  end

  def step(id) = { "id" => id, "name" => id, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 1 } }

  def read(turn = @turn, **arguments) = Chat::Tools::GetWorkflow.new(turn).call(**arguments.stringify_keys)

  def propose(turn = @turn, **arguments) = Chat::Tools::ProposeWorkflowEdit.new(turn).call(**arguments.stringify_keys)

  test "a chat beside the canvas tells Halon which workflow is open" do
    context = Conversation::Context.new(@conversation, @turn).current

    assert_includes context, "You are beside the canvas of the workflow Release check (release_check)"
  end

  test "it reads the workflow beside the chat, or one it names, as the gateway allows" do
    AbilityGateway.expects(:authorize!).twice.with { |arguments| arguments[:action_key] == Ability::Action::WORKFLOWS_READ }.returns(stub_everything)
    read_out = read

    assert_includes read_out, "\"name\": \"wait\""
    assert_includes read_out, "\"kind\": \"branch\""
    assert_includes read(workflow: "Release check"), "The live version 1."
  end

  test "a change of several edits is proposed as one, from this chat, for a person to accept" do
    answer = propose(edits: [ { operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { step: step("then") } },
                              { operation: Workflow::Edit::OPERATION_CONNECT, payload: { from: "wait", to: "then" } } ],
                     reason: "Waits again after the first wait.")

    assert_match "Proposed.", answer
    proposals = @workflow.proposals.to_a
    assert_equal [ Workflow::Edit::OPERATION_ADD_STEP, Workflow::Edit::OPERATION_CONNECT ], proposals.map(&:operation)
    assert_equal 1, proposals.map(&:change_set_id).uniq.size
    assert proposals.all?(&:by_halon?)
    assert_equal [ "Waits again after the first wait." ], proposals.map(&:reason).uniq
    assert_equal %w[wait], @workflow.reload.live_version.steps.map { |each| each["id"] }
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: Ability::Action::WORKFLOWS_CREATE)
  end

  test "a change that could never be accepted is refused before anyone sees it" do
    answer = propose(edits: [ { operation: Workflow::Edit::OPERATION_CONNECT, payload: { from: "wait", to: "nowhere" } } ], reason: "Connects it.")

    assert_equal "Both steps must be in the same part of the workflow. Nothing was proposed.", answer
    assert_empty @workflow.proposals
  end

  test "a workflow it cannot find, or a chat beside none, says so" do
    plain = Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @member), asker: @member)

    assert_equal "Name the workflow, since this chat was not started beside one.", read(plain)
    assert_equal "There is no workflow called Nightly in this workspace.", propose(plain, workflow: "Nightly", edits: [], reason: "x")
  end

  test "someone who may not change workflows is told so, and nothing is proposed" do
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::Denied.new(Ability::Action::WORKFLOWS_CREATE))

    answer = propose(edits: [ { operation: Workflow::Edit::OPERATION_REMOVE_STEP, payload: { step_id: "wait" } } ], reason: "Not needed.")

    assert_match Ability::Action::WORKFLOWS_CREATE, answer
    assert_empty @workflow.proposals
  end

  test "every workspace is offered them" do
    names = Conversation::Tools.for(@turn, offer: []).map(&:name)
    assert_includes names, Chat::Tools::GetWorkflow::NAME
    assert_includes names, Chat::Tools::ProposeWorkflowEdit::NAME
  end
end
