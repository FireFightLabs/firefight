require "test_helper"

# A saved runbook Halon runs by name: confirmed by the person first, each step run as them, stopped at the first step
# that does not go through, and its watch started once every step did.
class Conversation::Tools::RunRunbookTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
  end

  test "a runbook Halon can run is saved from a chat with its tool steps, inputs, other names and watch" do
    upsert = Chat::Tools.catalog(turn(@admin)).find { |entry| entry.name.to_s == Mcp::Tools::UPSERT_RUNBOOK }.tool

    upsert.call(
      name: "Release Firefight", aliases: [ "release firefight", "ship it" ],
      inputs: [ { key: "bump", question: "Which version bump?", default: "patch" } ],
      steps: [ { title: "Start the release", tool: "search_incidents", arguments: { query: "release {{bump}}" } },
               { title: "Tell the team" } ],
      watch: { title: "release", steps: [ { label: "Release run", capability: "run_history", resource: "firefight", name: "{{bump}}" } ] }
    )

    runbook = @workspace.runbooks.active.find_by!(name: "Release Firefight")
    assert_equal [ "release firefight", "ship it" ], runbook.aliases
    assert_equal [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], runbook.inputs
    assert_equal [ [ "search_incidents", { "query" => "release {{bump}}" } ], [ nil, {} ] ], runbook.runbook_steps.map { |step| [ step.tool, step.arguments ] }
    assert_equal "{{bump}}", runbook.watch["steps"].first["name"]
    assert runbook.procedure?
    assert_equal runbook, Runbook.named(@workspace.runbooks.active, "Ship It")
  end

  test "a step that names an input the runbook does not ask for is refused when saved" do
    runbook = @workspace.runbooks.create!(name: "Release Firefight")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      runbook.sync_steps!([ { title: "Start", tool: "search_incidents", arguments: { "query" => "{{version}}" } } ])
    end

    assert_match "{{version}}", error.message
  end

  test "running one always waits for the person, who is shown each step and the watch with the inputs filled in" do
    release_runbook
    tool = Conversation::Tools::RunRunbook.new(turn(@member))
    call = RubyLLM::ToolCall.new(id: "call_1", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "ship it", "inputs" => { "bump" => "minor" } })
    @conversation.chat_record.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { "call_1" => call }))

    assert tool.requires_approval?
    assert_nil tool.approval_resolver.call(call)

    asked = Chat::Tools.confirmation(@conversation.chat.tool_calls.find_by!(tool_call_id: "call_1")).asked
    assert_includes asked, [ "Step 1: Look for past releases", "search_incidents {\"query\":\"release minor\"}" ]
    assert_includes asked, [ "Then watch", "release: Release run" ]
  end

  test "a request that cannot run is let through at once, so Halon hears why and nobody is asked" do
    release_runbook(default: nil)
    tool = Conversation::Tools::RunRunbook.new(turn(@member))
    call = RubyLLM::ToolCall.new(id: "call_2", name: Conversation::Tools::RunRunbook::NAME, arguments: { "runbook" => "Release Firefight" })

    assert tool.approval_resolver.call(call)
    assert_match "Which version bump?", tool.call(runbook: "Release Firefight")
    assert_match "No runbook is called deploy everything", tool.call(runbook: "deploy everything")
  end

  test "each step runs as the person in order, and once every step went through the watch starts with the inputs filled in" do
    runbook = release_runbook
    Conversation::Watches.expects(:start).with { |turn, spec| turn.asker == @member && spec["steps"].first["name"] == "minor" }
                         .returns("This usually takes about 18 minutes, I will watch for up to 40.")

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: runbook.slug, inputs: { "bump" => "minor" })

    assert_match "Step 1 (Look for past releases) went through", said
    assert_match "Every step of Release Firefight went through.", said
    assert_match "I will watch for up to 40.", said
  end

  test "a connection's change the person may not make names the pack to ask an admin for" do
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.integration_environments.create!
    restart = northflank.tools.create!(name: "restart_service", read_only: false, enabled: true)
    runbook = release_runbook
    runbook.sync_steps!([ { title: "Restart web", tool: restart.model_facing_name, arguments: {} } ])

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: runbook.name, inputs: { "bump" => "patch" })

    assert_match "may not use #{restart.model_facing_name}. Needs the Faylee (Northflank): changes pack, which a workspace admin can give.", said
  end

  test "a change the person may not make stops the run with the reason, and nothing after it runs or is watched" do
    runbook = release_runbook
    runbook.sync_steps!([
      { title: "Give the bot access", tool: Mcp::Tools::GRANT_ABILITY, arguments: { "principal_kind" => "user", "principal_id" => @member.id, "ability" => "alerts.update" } },
      { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "release" } }
    ])
    Conversation::Watches.expects(:start).never

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: runbook.name, inputs: { "bump" => "patch" })

    assert_match "Step 1 (Give the bot access) was not run", said
    assert_match "may not use grant_ability", said
    assert_no_match "Step 2", said
    assert_empty Ability::Grant.where(principal: @member)
  end

  test "a step its tool refuses stops the run there with what the tool said" do
    runbook = release_runbook
    runbook.sync_steps!([
      { title: "Note the release", tool: "create_action_item", arguments: { "incident" => "INC-99999", "description" => "Release" } },
      { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "release" } }
    ])
    Conversation::Watches.expects(:start).never

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: runbook.name, inputs: { "bump" => "patch" })

    assert_match "Step 1 (Note the release) failed, so the run stopped there.", said
    assert_no_match "Step 2", said
  end

  test "a step an approval rule holds stops the run there, waiting, and nothing after it runs or is watched" do
    runbook = release_runbook
    runbook.sync_steps!([
      { title: "Note the release", tool: "create_action_item", arguments: { "incident" => @incident.identifier, "description" => "Release" } },
      { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "release" } }
    ])
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    Conversation::Watches.expects(:start).never

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: runbook.name, inputs: { "bump" => "patch" })

    assert_match "Step 1 (Note the release) is waiting for an approval, so the run stopped there.", said
    assert_no_match "Step 2", said
    assert_not @incident.incident_actions.exists?(description: "Release")
  end

  test "once every step went through, the runbook's watch starts for real, its inputs filled in" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    row = github.integration_environments.create!(credentials: { token: "x" }.to_json)
    github.tools.create!(name: "ci_runs", description: "CI runs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, external_id: "acme/firefight",
                                  name: "firefight", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
    took = Array.new(3) { |index| Integrations::Capabilities::History::Run.new(id: index.to_s, name: "minor", status: "succeeded", started_at: (index + 1).days.ago, finished_at: (index + 1).days.ago + 18.minutes) }
    Integrations::NativeExecutor.stubs(:call).returns(Integrations::Capabilities::History.result(took, what: "acme/firefight"))

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: release_runbook.slug, inputs: { "bump" => "minor" })

    assert_match "This usually takes about 18 minutes, I will watch for up to 40.", said
    watch = @conversation.chat.watches.sole
    assert_equal [ @member, "minor" ], [ watch.asker, watch.steps.sole.run_name ]
  end

  test "a runbook with no tool steps is followed by hand, as before" do
    runbook = @workspace.runbooks.create!(name: "Database failover")
    runbook.sync_steps!([ { title: "Page the DBA" } ])

    assert_not runbook.procedure?
    assert_match "has no step for Halon to run", Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: "Database failover")
  end

  test "with workflows on, running a runbook starts the workflow it links as the workflow's own identity, with the inputs given" do
    runbook = release_runbook
    workflow = published_workflow_of(runbook)

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: "ship it", inputs: { "bump" => "minor" })

    run = workflow.runs.sole
    assert_match "Started Release Firefight, the workflow Release Firefight runs. Its run: ", said
    assert_includes said, Workflow::Links.run(run)
    assert_equal [ workflow.agent, Workflow::Run::STARTED_BY_HALON, @member ], [ run.agent, run.started_by_kind, run.started_by ]
    assert_equal({ "bump" => "minor" }, run.inputs)
    assert_equal({ "name" => "Release Firefight", "slug" => runbook.slug }, run.trigger_payload["runbook"])
    assert Ability::Invocation.exists?(principal: @member, action_key: Workflow::CREATE_KEY), "starting it is ledgered as running a workflow"
    assert_not Chat::Watch.exists?(asker: @member), "the workflow's watch step watches as the workflow, not the chat as the person"
  end

  test "with workflows on, the confirmation shows the workflow's steps and the inputs it runs with" do
    runbook = release_runbook
    published_workflow_of(runbook)

    rows = Conversation::Tools::RunRunbook.plan_rows(@workspace, "runbook" => "ship it", "inputs" => { "bump" => "minor" })

    assert_includes rows, [ "Input bump", "minor" ]
    assert_includes rows.map(&:first), "Call a tool"
    assert_includes rows.map(&:first), "Watch"
  end

  test "with workflows on, a runbook whose workflow is a draft says so with its page, and one with none is followed by hand" do
    runbook = release_runbook
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    tool = Conversation::Tools::RunRunbook.new(turn(@member))

    said = tool.call(runbook: "ship it", inputs: { "bump" => "minor" })
    assert_match "Release Firefight has no published version to run. Its page: ", said
    assert_includes said, Workflow::Links.page(runbook.reload.workflow)
    assert_empty runbook.workflow.runs

    guide = @workspace.runbooks.create!(name: "Database failover")
    assert_match "Database failover links no workflow, so a person follows it by hand.", tool.call(runbook: "Database failover")
  end

  test "with workflows on, an input with no value and no default is asked for first" do
    published_workflow_of(release_runbook(default: nil))

    said = Conversation::Tools::RunRunbook.new(turn(@member)).call(runbook: "Release Firefight")

    assert_match "Ask the person first: Which version bump?", said
  end

  test "Halon is told runbooks start their workflow only where the workspace has workflows" do
    assert_equal Conversation::Tools::RunRunbook.description, Conversation::Tools::RunRunbook.new(turn(@member)).description

    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)

    assert_equal Conversation::Tools::RunRunbook::WORKFLOW_DESCRIPTION, Conversation::Tools::RunRunbook.new(turn(@member)).description
  end

  private

  def turn(asker) = Conversation::Turn.new(@conversation, asker: asker)

  def published_workflow_of(runbook)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = runbook.reload.workflow
    result = WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @admin)
    assert result.ok, result.words
    workflow.reload
  end

  def release_runbook(default: "patch")
    runbook = @workspace.runbooks.create!(
      name: "Release Firefight", aliases: [ "ship it" ],
      inputs: [ { "key" => "bump", "question" => "Which version bump?", "default" => default } ],
      watch: { "title" => "release", "steps" => [ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "{{bump}}" } ] }
    )
    runbook.sync_steps!([ { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "release {{bump}}" } } ])
    runbook
  end
end
