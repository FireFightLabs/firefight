require "test_helper"

# Where a workspace has workflows, a runbook is a guide and what it ran moves into a workflow it links. Every field a
# runbook held is accounted for: what it runs in the workflow, the rest on the runbook as it was.
class Runbook::LinkedWorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @runbook = release_runbook
  end

  test "each step that calls a tool becomes a step calling the same tool, named after its title, in the same order" do
    workflow = moved

    steps = workflow.draft.steps
    assert_equal %w[call_tool call_tool watch], steps.map { |step| step["kind"] }
    assert_equal %w[look_for_past_releases start_the_release], steps.first(2).map { |step| step["name"] }
    assert_equal %w[search_incidents search_incidents], steps.first(2).map { |step| step.dig("config", "tool") }
  end

  test "a step's arguments are kept, with each input it names read from the run's inputs" do
    steps = moved.draft.steps

    assert_equal({ "query" => "release {{inputs.bump}}", "limit" => 5 }, steps.first.dig("config", "arguments"))
    assert_equal({ "query" => "{{inputs.bump}}", "status" => [ "active", "resolved" ] }, steps.second.dig("config", "arguments"))
  end

  test "the steps run one after another, and the watch after the last of them" do
    draft = moved.draft
    ids = draft.steps.map { |step| step["id"] }

    assert_equal [ { "from" => ids[0], "to" => ids[1] }, { "from" => ids[1], "to" => ids[2] } ], draft.edges
  end

  test "the inputs become the questions a run asks, each with its default" do
    trigger = moved.draft.trigger

    assert_equal Workflow::Trigger::KIND_MANUAL, trigger["kind"]
    assert_equal [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" },
                   { "key" => "note", "question" => "Anything to say?" } ], trigger["inputs"]
  end

  test "the watch becomes a watch step with the same spec, its inputs read from the run's inputs" do
    watch = moved.draft.steps.last

    assert_equal "watch", watch["name"]
    assert_equal "release", watch.dig("config", "title")
    assert_equal 30, watch.dig("config", "minutes")
    assert_equal [ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "{{inputs.bump}}" } ],
                 watch.dig("config", "steps")
  end

  test "the workflow takes the runbook's name, its other names and its summary as what it does" do
    workflow = moved

    assert_equal "Release Firefight", workflow.name
    assert_equal "release_firefight", workflow.slug
    assert_equal [ "release firefight", "ship it" ], workflow.aliases
    assert_equal "Releases Firefight to production.", workflow.description
    assert_equal workflow, Workflow.named(@workspace.workflows, "ship it")
  end

  test "it is a draft written by Firefight that nobody published, so an admin publishes it and grants it what it needs" do
    workflow = moved

    assert_not workflow.live?
    assert_nil workflow.agent
    draft = workflow.draft
    assert_equal 1, draft.number
    assert_equal Workflow::AUTHOR_FIREFIGHT, draft.author_kind
    assert_equal "Moved from the Release Firefight runbook, which keeps its steps as a checklist.", draft.reason
  end

  test "the runbook links it and keeps every step as a checklist item with its id, title and instruction" do
    before = @runbook.runbook_steps.map { |step| [ step.id, step.position, step.title, step.instruction ] }
    workflow = moved

    @runbook.reload
    assert_equal workflow, @runbook.workflow
    assert_equal before, @runbook.runbook_steps.map { |step| [ step.id, step.position, step.title, step.instruction ] }
    assert @runbook.runbook_steps.none?(&:tool?)
    assert @runbook.runbook_steps.all? { |step| step.arguments == {} }
  end

  test "the runbook no longer asks inputs or watches, but keeps its other names, content, link and how it attaches" do
    @runbook.update!(always_attach: true)
    @runbook.incident_conditions.create!(workspace: @workspace, condition_field: IncidentCondition::FIELD_SEVERITY, operator: IncidentCondition::OPERATOR_ONE_OF,
                                         values: [ incident_severities(:critical_ws1).id ])
    moved

    @runbook.reload
    assert_equal [], @runbook.inputs
    assert_nil @runbook.watch
    assert_equal [ "release firefight", "ship it" ], @runbook.aliases
    assert_equal "Bump the version, then watch the release.", @runbook.content
    assert_equal "https://wiki.example.com/release", @runbook.external_url
    assert @runbook.always_attach?
    assert_equal 1, @runbook.incident_conditions.count
    assert_equal Runbook::ATTACH_CONDITIONAL, @runbook.attach_mode
  end

  test "an action claimed from a step that called a tool keeps its step, and the step can still be claimed in an incident" do
    incident = incidents(:active_critical_ws1)
    tool_step = @runbook.runbook_steps.find_by!(title: "Start the release")
    Slack::WorkspaceAdapter.any_instance.stubs(:post_runbook_message).returns(message_id: "1.2")
    attached = RunbookAttachmentService.new(@workspace).attach(incident: incident, runbook: @runbook)
    action = incident.incident_actions.create!(description: tool_step.title, runbook_step: tool_step, created_by: @admin, assignee: @admin,
                                               status: IncidentAction::STATUS_IN_PROGRESS)

    moved

    assert_equal tool_step.id, action.reload.runbook_step_id
    assert_equal "Release Firefight", action.origin_reference.label
    assert_equal action, attached.reload.actions_by_step[tool_step.id]
    assert_includes attached.runbook.runbook_steps.map(&:id), tool_step.id
  end

  test "a step given an undo keeps it, and a plain guide with nothing to run gets no workflow" do
    guide = @workspace.runbooks.create!(name: "Database failover", content: "Fail over.")
    guide.runbook_steps.create!(title: "Promote the replica", position: 1)

    assert_nil guide.move_runnable_parts!
    assert_nil guide.reload.workflow
    assert_equal [ "Promote the replica" ], guide.runbook_steps.map(&:title)
  end

  test "a name another workflow answers to is kept free, and the moved one says it came from a runbook" do
    Workflow.create!(workspace: @workspace, name: "Release Firefight")

    workflow = moved

    assert_equal "Release Firefight runbook", workflow.name
    assert_equal "release_firefight_runbook", workflow.slug
  end

  test "an other name another workflow answers to stays the runbook's own" do
    Workflow.create!(workspace: @workspace, name: "Deploy", aliases: [ "ship it" ])

    assert_equal [ "release firefight" ], moved.aliases
    assert_equal [ "release firefight", "ship it" ], @runbook.reload.aliases
  end

  test "a runbook only moves once, and a disabled one moves too" do
    @runbook.update!(deleted_at: Time.current)
    enable_workflows

    workflows = Runbook.move_runnable_parts!(@workspace)

    assert_empty workflows, "turning workflows on already moved it"
    assert_equal 1, @workspace.workflows.where(name: "Release Firefight").count
    assert @runbook.reload.workflow
  end

  test "two moves of the same runbook at once make one workflow, and the one that lost takes its own back out" do
    stale = Runbook.includes(:runbook_steps).find(@runbook.id)
    first = moved

    assert_nil stale.move_runnable_parts!
    assert_equal [ first ], @workspace.workflows.to_a
    assert_equal first, @runbook.reload.workflow
  end

  test "a runbook holding a value shaped like a secret is left as it was, since a workflow never keeps one" do
    @runbook.runbook_steps.first.update!(arguments: { "query" => "{{bump}}", "token" => "ghp_#{'a' * 36}" })

    assert_nil moved
    assert_nil @runbook.reload.workflow
    assert @runbook.runbook_steps.any?(&:tool?)
    assert_empty @workspace.workflows
  end

  test "turning workflows on moves every runbook of that workspace and no other" do
    other = workspaces(:slack_workspace_two).runbooks.create!(name: "Rollback", inputs: [ { key: "service", question: "Which service?" } ])

    enable_workflows

    assert @runbook.reload.workflow
    assert_nil other.reload.workflow
    assert_equal [ { "key" => "service", "question" => "Which service?" } ], other.inputs
  end

  test "without workflows nothing moves" do
    assert_empty Runbook.move_runnable_parts!(@workspace)
    assert_nil @runbook.reload.workflow
    assert @runbook.procedure?
  end

  test "the parts read back from the workflow are the runbook's own" do
    parts = @runbook.own_parts

    assert_equal parts.steps.map { |step| step.slice("tool", "arguments") }, Runbook::WorkflowShape.parts_of(moved.draft).steps.map { |step| step.slice("tool", "arguments") }
    assert_equal parts.inputs, Runbook::WorkflowShape.parts_of(@runbook.workflow.draft).inputs
    assert_equal parts.watch, Runbook::WorkflowShape.parts_of(@runbook.workflow.draft).watch
  end

  test "a workflow changed into something a runbook cannot say does not read back as a runbook's parts" do
    draft = moved.draft
    branched = draft.edges.map { |edge| edge.merge("route" => "yes") }

    assert_nil Runbook::WorkflowShape.parts_of(Workflow::Version.new(trigger: draft.trigger, steps: draft.steps, edges: branched, outputs: {}))
    retried = draft.steps.map { |step| step.merge("retry" => { "max_attempts" => 3 }) }
    assert_nil Runbook::WorkflowShape.parts_of(Workflow::Version.new(trigger: draft.trigger, steps: retried, edges: draft.edges, outputs: {}))
  end

  test "the migration moves the runbooks of workspaces with workflows and leaves the others exactly as they are" do
    require Rails.root.join("db/migrate/20261013180100_move_runbook_steps_into_workflows")
    other = workspaces(:slack_workspace_two).runbooks.create!(name: "Rollback", watch: { "title" => "web", "steps" => [ { "capability" => "resource_status", "resource" => "web", "goal" => "up" } ] })
    Flipper.enable_actor(FeatureFlags::WORKFLOWS, @workspace)

    ActiveRecord::Migration.suppress_messages { MoveRunbookStepsIntoWorkflows.new.up }

    assert_equal "Release Firefight", @runbook.reload.workflow.name
    assert_nil other.reload.workflow
    assert_equal "web", other.watch["title"]
  end

  private

  def release_runbook
    runbook = @workspace.runbooks.create!(
      name: "Release Firefight", summary: "Releases Firefight to production", content: "Bump the version, then watch the release.",
      external_url: "https://wiki.example.com/release", aliases: [ "release firefight", "ship it" ],
      inputs: [ { key: "bump", question: "Which version bump?", default: "patch" }, { key: "note", question: "Anything to say?" } ],
      watch: { "title" => "release", "minutes" => 30, "steps" => [ { "label" => "Release run", "capability" => "run_history", "resource" => "firefight", "name" => "{{bump}}" } ] }
    )
    runbook.sync_steps!([
      { title: "Look for past releases", instruction: "So the bump matches.", tool: "search_incidents", arguments: { "query" => "release {{bump}}", "limit" => 5 } },
      { title: "Tell the team", instruction: "In #releases." },
      { title: "Start the release", tool: "search_incidents", arguments: { "query" => "{{bump}}", "status" => [ "active", "resolved" ] } }
    ])
    runbook.reload
  end

  def moved
    Flipper.enable_actor(FeatureFlags::WORKFLOWS, @workspace)
    @runbook.reload.move_runnable_parts!
  end

  def enable_workflows = FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
end
