require "test_helper"

# A saved runbook Halon runs by name: confirmed by the person first, it starts the workflow the runbook links as that
# workflow's own identity.
class Conversation::Tools::RunRunbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "a step that names an input the runbook does not ask for is refused when saved" do
    runbook = @workspace.runbooks.create!(name: "Release Firefight")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      runbook.sync_steps!([ { title: "Start", tool: "search_incidents", arguments: { "query" => "{{version}}" } } ])
    end

    assert_match "{{version}}", error.message
  end

  test "running one always waits for the person, who is shown the workflow's steps and the inputs it runs with" do
    published_workflow_of(release_runbook)
    tool = Conversation::Tools::RunRunbook.new(turn(@member))
    call = RubyLLM::ToolCall.new(id: "call_1", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "ship it", "inputs" => { "bump" => "minor" } })
    @conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => call }))

    assert tool.requires_approval?
    assert_nil tool.approval_resolver.call(call)

    asked = Chat::Tools.confirmation(@conversation.chat.tool_calls.find_by!(tool_call_id: "call_1")).asked
    assert_includes asked, [ "Input bump", "minor" ]
  end

  test "a request that cannot run is let through at once, so Halon hears why and nobody is asked" do
    published_workflow_of(release_runbook(default: nil))
    tool = Conversation::Tools::RunRunbook.new(turn(@member))
    call = RubyLLM::ToolCall.new(id: "call_2", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "Release Firefight" })

    assert tool.approval_resolver.call(call)
    assert_match "Ask the person first: Which version bump?", tool.call(runbook: "Release Firefight")
    assert_match "No runbook is called deploy everything", tool.call(runbook: "deploy everything")
  end

  test "the person's own Approve on this run's card answers its steps" do
    workflow = published_workflow_of(release_runbook)
    chat = @conversation.chat_record
    approved = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
                   .ruby_llm_tool_calls.create!(tool_call_id: "call_ok", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "ship it" })
    chat.request_decisions!([ "call_ok" ])
    chat.decide!("call_ok", approved: true, by: @member)

    Conversation::Tools::RunRunbook.new(turn(@member)).call(tool_call: RubyLLM::ToolCall.new(id: "call_ok", name: approved.name, arguments: {}),
                                                            runbook: "ship it", inputs: { "bump" => "minor" })
    assert_equal @member, workflow.runs.sole.confirmed_by
  end

  test "Allow for the rest of the chat runs a runbook without a card, and its yes answers none of the steps" do
    workflow = published_workflow_of(release_runbook)
    chat = @conversation.chat_record
    chat.allow_tool!(Conversation::Tools::RunRunbook::NAME)
    allowed = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
                  .ruby_llm_tool_calls.create!(tool_call_id: "call_allowed", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "ship it" })
    Conversation::Tools::RunRunbook.new(turn(@member)).call(tool_call: RubyLLM::ToolCall.new(id: "call_allowed", name: allowed.name, arguments: {}),
                                                            runbook: "ship it", inputs: { "bump" => "minor" })
    assert_nil workflow.runs.sole.confirmed_by
  end

  test "running a runbook starts the workflow it links as the workflow's own identity, with the inputs given" do
    runbook = release_runbook
    workflow = published_workflow_of(runbook)

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: "ship it", inputs: { "bump" => "minor" })

    run = workflow.runs.sole
    assert_match "Started Release Firefight, the workflow Release Firefight runs. Its run: ", said
    assert_includes said, Workflow::Links.run(run)
    assert_equal [ workflow.agent, Workflow::Run::STARTED_BY_HALON, @member, nil ], [ run.agent, run.started_by_kind, run.started_by, run.confirmed_by ],
                 "a call with no card the person approved confirms nothing for its steps"
    assert_equal({ "bump" => "minor" }, run.inputs)
    assert_equal({ "name" => "Release Firefight", "slug" => runbook.slug }, run.trigger_payload["runbook"])
    assert Ability::Invocation.exists?(principal: @member, action_key: Workflow::CREATE_KEY), "starting it is ledgered as running a workflow"
    assert_not Chat::Watch.exists?(asker: @member), "the workflow's watch step watches as the workflow, not the chat as the person"
  end

  test "the confirmation shows the workflow's steps and the inputs it runs with" do
    runbook = release_runbook
    published_workflow_of(runbook)

    rows = Conversation::Tools::RunRunbook.plan_rows(@workspace, "runbook" => "ship it", "inputs" => { "bump" => "minor" })

    assert_includes rows, [ "Input bump", "minor" ]
    assert_includes rows.map(&:first), "Call a tool"
    assert_includes rows.map(&:first), "Watch"
  end

  test "a runbook whose workflow is a draft says so with its page, and one with none is followed by hand" do
    runbook = release_runbook
    tool = Conversation::Tools::RunRunbook.new(turn(@member))

    said = tool.call(runbook: "ship it", inputs: { "bump" => "minor" })
    assert_match "Release Firefight has no published version to run. Its page: ", said
    assert_includes said, Workflow::Links.page(runbook.workflow)
    assert_empty runbook.workflow.runs

    @workspace.runbooks.create!(name: "Database failover")
    assert_match "Database failover links no workflow, so a person follows it by hand.", tool.call(runbook: "Database failover")
  end

  private

  def turn(asker) = Conversation::Turn.new(@conversation, asker: asker)

  def published_workflow_of(runbook)
    workflow = runbook.workflow
    result = WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @admin)
    assert result.ok, result.words
    workflow.reload
  end

  # Saved with what it runs and moved into the workflow it links, as every runbook's was.
  def release_runbook(default: "patch")
    runbook = @workspace.runbooks.create!(
      name: "Release Firefight", aliases: [ "ship it" ],
      inputs: [ { "key" => "bump", "question" => "Which version bump?", "default" => default } ],
      watch: { "title" => "release", "steps" => [ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "{{bump}}" } ] }
    )
    runbook.sync_steps!([ { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "release {{bump}}" } } ])
    runbook.reload.move_runnable_parts!
    runbook.reload
  end
end
