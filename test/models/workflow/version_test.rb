require "test_helper"

class Workflow::VersionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @workflow = Workflow.create!(workspace: @workspace, name: "Check")
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def draft_with(steps:, edges: [], trigger: Workflow::Trigger.default, outputs: {})
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(steps: steps, edges: edges, trigger: trigger, outputs: outputs)
    draft
  end

  test "a draft is opened once, numbered, and says who made it" do
    draft = @workflow.open_draft!(by: @alice, reason: "Started it.")

    assert_equal draft, @workflow.open_draft!(by: @bob)
    assert_equal 1, draft.number
    assert draft.draft?
    assert_equal Workflow::AUTHOR_PERSON, draft.author_kind
    assert_equal @alice, draft.author
    assert_equal({ "kind" => "manual", "inputs" => [] }, draft.trigger)
  end

  test "publishing makes it live, retires the version that was, and opens the next draft from it" do
    first = draft_with(steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    first.publish!(by: @alice)

    assert first.live?
    assert_equal first, @workflow.reload.live_version
    assert_equal @alice, first.published_by

    second = @workflow.open_draft!(by: @bob)
    assert_equal first, second.parent_version
    assert_equal first.steps, second.steps
    assert_equal 2, second.number
    second.publish!(by: @alice)

    assert_equal Workflow::Version::STATUS_RETIRED, first.reload.status
    assert_equal second, @workflow.reload.live_version
  end

  test "publishing refuses a draft with problems, and one changed since the publisher looked" do
    broken = draft_with(steps: [ step("pause", "teleport") ])
    error = assert_raises(Workflow::Edit::Refused) { broken.publish!(by: @alice) }
    assert_match "cannot be published yet", error.message

    broken.update!(steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    seen = broken.revision
    Workflow::Version.where(id: broken.id).update_all(revision: seen + 1)
    assert_raises(Workflow::Edit::Refused) { broken.publish!(by: @alice, revision: seen) }
    assert broken.reload.draft?
  end

  test "a published version never changes" do
    version = draft_with(steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    version.publish!(by: @alice)

    assert_not version.update(steps: [])
    assert_includes version.errors[:base], "A published version never changes, so change its draft instead."
  end

  test "restoring an old version makes a new draft from it, and waits for an open draft to go" do
    first = draft_with(steps: [ step("pause", "delay", { "seconds" => 1 }) ])
    first.publish!(by: @alice)
    second = draft_with(steps: [ step("pause", "delay", { "seconds" => 9 }) ])

    assert_equal "Publish or discard the open draft first.", first.restore_blocked_reason
    second.publish!(by: @alice)

    restored = first.restore!(by: @bob)
    assert restored.draft?
    assert_equal 3, restored.number
    assert_equal first, restored.parent_version
    assert_equal({ "seconds" => 1 }, restored.steps.first["config"])
    assert_equal "Restored version 1.", restored.reason
  end

  test "a thrown away draft makes room for another" do
    draft = @workflow.open_draft!(by: @alice)
    draft.discard!

    assert_equal Workflow::Version::STATUS_DISCARDED, draft.status
    assert_not_equal draft, @workflow.open_draft!(by: @alice)
  end

  test "a step reads only the trigger's inputs and the steps that run before it" do
    draft = draft_with(
      trigger: { "kind" => "manual", "inputs" => [ { "key" => "region", "question" => "Which region?" } ] },
      steps: [ step("first", "delay", { "seconds" => "{{inputs.region}}" }), step("second", "delay", { "seconds" => "{{steps.first.waited_until}}" }),
               step("side", "delay", { "seconds" => "{{steps.second.x}} {{inputs.zone}} {{item}} {{weather.today}} {{trigger.incident.id}}" }) ],
      edges: [ { "from" => "first", "to" => "second" }, { "from" => "first", "to" => "side" } ],
      outputs: { "region" => "{{inputs.region}}", "ghost" => "{{steps.ghost.x}}" }
    )

    problems = draft.problems
    assert_includes problems, "side uses {{steps.second.x}}, which is not a step that runs before it."
    assert_includes problems, "side uses {{inputs.zone}}, which is not one of the trigger's inputs."
    assert_includes problems, "side uses {{item}}, which only a step inside a for each can read."
    assert_includes problems, "side uses {{weather.today}}, which is not something a step can read."
    assert_includes problems, "The outputs use {{steps.ghost.x}}, which is not a step in the workflow."
    assert_equal 5, problems.size
  end

  test "a step inside a for each reads its item and the steps before the loop" do
    draft = draft_with(
      steps: [ step("list", "delay", { "seconds" => 0 }),
               step("each", "for_each", { "items" => "{{steps.list.names}}", "steps" => [ step("look", "delay", { "seconds" => "{{item}} {{index}} {{steps.list.waited_until}}" }) ], "edges" => [] }) ],
      edges: [ { "from" => "list", "to" => "each" } ]
    )

    assert_empty draft.problems
  end

  test "the trigger needs a known kind and well formed inputs" do
    draft = draft_with(trigger: { "kind" => "telepathy", "inputs" => [ { "key" => "Bad Key", "question" => "?" }, { "key" => "ok" } ] },
                       steps: [ step("pause", "delay", { "seconds" => 1 }) ])

    problems = draft.problems
    assert_includes problems, "The trigger is a telepathy trigger, which is not a kind of trigger."
    assert_includes problems, "Inputs need keys of lowercase letters, numbers and underscores, such as region."
    assert_includes problems, "The trigger needs a question for ok."
  end

  test "fills references keeping a lone reference's type" do
    scope = { "inputs" => { "count" => 3 }, "steps" => { "check" => { "hosts" => %w[a b] } } }

    assert_equal 3, Workflow::Version.filled("{{inputs.count}}", scope)
    assert_equal %w[a b], Workflow::Version.filled("{{ steps.check.hosts }}", scope)
    assert_equal "b", Workflow::Version.filled("{{steps.check.hosts.1}}", scope)
    assert_equal "3 hosts, gone", Workflow::Version.filled("{{inputs.count}} hosts, {{steps.missing.x}}gone", scope)
    assert_nil Workflow::Version.filled("{{steps.missing.x}}", scope)
  end
end
