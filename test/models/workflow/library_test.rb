require "test_helper"

class Workflow::LibraryTest < ActiveSupport::TestCase
  # Step kinds the shipped library items name that the runtime does not run yet. An item using one is listed but cannot
  # be taken, and this list shrinks as the runtime learns them.
  NOT_YET_RUN = %w[run_skill raise_notice].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "making its own agent inside someone else's transaction leaves no agent behind when another caller made one first" do
    workflow = Workflow.create!(workspace: workspaces(:slack_workspace_one), name: "Raced", created_by: workspace_memberships(:alice_workspace_one))
    other = Workflow.find(workflow.id).ensure_agent!

    ActiveRecord::Base.transaction do
      assert_no_difference -> { Agent.count } do
        assert_equal other, workflow.ensure_agent!
      end
    end
  end

  def definition(minutes: 5, extra: [])
    {
      "trigger" => { "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [] },
      "steps" => [ { "id" => "step_wait", "name" => "wait", "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => minutes } }, *extra ],
      "edges" => [], "outputs" => {}
    }
  end

  def item(version: 1, **options)
    Workflow::Library::Item.new(key: "cool_down", name: "Cool down", description: "Waits a while.", aliases: [ "pause" ],
                                definition: definition(**options), version: version)
  end

  def offer(*items)
    Workflow::Library.stubs(:all).returns(items)
  end

  test "every shipped item reads, says what it does, and holds a well formed workflow whose only gap is steps the runtime does not run yet" do
    assert Workflow::Library.all.any?
    Workflow::Library.all.each do |shipped|
      assert shipped.name.present? && shipped.description.present?, "#{shipped.key} has a name and says what it does"
      assert_nil Workflow::Version.content_problem(shipped.definition), "#{shipped.key} holds a well formed workflow"
      kinds = Workflow::Version.all_steps(shipped.definition["steps"]).map { |step| step["kind"] }
      gaps = shipped.problems.reject { |problem| NOT_YET_RUN.any? { |kind| problem.include?("is a #{kind} step") } }
      assert_empty gaps, "#{shipped.key} has no problem beyond steps the runtime does not run yet"
      assert_equal shipped.available?, (kinds & NOT_YET_RUN).empty?
    end
  end

  test "each check Halon runs on a schedule has a library workflow that runs its skill" do
    skills = Workflow::Library.all.flat_map { |shipped| Workflow::Version.all_steps(shipped.definition["steps"]).filter_map { |step| step.dig("config", "skill") } }

    Investigation::Check::KIND_DETAILS.values.filter_map(&:skill).each { |skill| assert_includes skills, skill }
  end

  test "an item is used as it is in a draft that follows the library, and a name already taken is refused" do
    offer(item)

    workflow = Workflow.from_library!(item, workspace: @workspace, by: @alice)

    assert_equal [ "Cool down", "cool_down", 1, true, [ "pause" ] ], workflow.values_at(:name, :library_key, :library_version, :follows_library, :aliases)
    draft = workflow.draft
    assert_equal [ Workflow::AUTHOR_FIREFIGHT, "From Firefight's library, version 1.", definition["steps"] ], [ draft.author_kind, draft.reason, draft.steps ]
    assert workflow.following_library?
    error = assert_raises(Workflow::Edit::Refused) { Workflow.from_library!(item, workspace: @workspace, by: @alice) }
    assert_equal "Cool down already exists here, so give this one another name.", error.message
    assert Workflow.from_library!(item, workspace: @workspace, by: @alice, name: "Cool down twice", following: false)
  end

  test "an item the runtime cannot run yet is not taken" do
    unrunnable = item(extra: [ { "id" => "step_x", "name" => "notice", "kind" => "raise_notice", "config" => {} } ])

    error = assert_raises(Workflow::Edit::Refused) { Workflow.from_library!(unrunnable, workspace: @workspace, by: @alice) }
    assert_match "needs steps this version of Firefight cannot run yet", error.message
  end

  test "a workflow following the library moves to a new version with its own trigger, and its draft moves along" do
    offer(item)
    workflow = Workflow.from_library!(item, workspace: @workspace, by: @alice)
    workflow.draft.publish!(by: @alice)
    workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, by: @alice,
                   payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [ { "key" => "why", "question" => "Why?" } ] } })
    newer = item(version: 2, minutes: 10)
    offer(newer)

    Workflow::Library.upgrade_all!

    workflow.reload
    live = workflow.live_version
    assert_equal [ 10, Workflow::AUTHOR_FIREFIGHT, 2 ], [ live.steps.first.dig("config", "minutes"), live.author_kind, workflow.library_version ]
    assert_equal [], Workflow::Trigger.input_keys(live.trigger), "the live trigger stays the one that was live"
    assert_equal 10, workflow.draft.steps.first.dig("config", "minutes"), "the draft whose steps were Firefight's moves too"
    assert_equal [ "why" ], Workflow::Trigger.input_keys(workflow.draft.trigger)
    assert workflow.following_library?
    assert_nil workflow.library_update
  end

  test "one workflow that fails to move on neither stops the others nor keeps half of its own move" do
    offer(item)
    first = Workflow.from_library!(item, workspace: @workspace, by: @alice, name: "First")
    second = Workflow.from_library!(item, workspace: @workspace, by: @alice, name: "Second")
    [ first, second ].each { |workflow| workflow.draft.publish!(by: @alice) }
    # A trigger that holds something shaped like a token, which no new version may carry, so moving it on fails.
    first.reload.live_version.update_columns(trigger: { "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [], "note" => "ghp_#{'a' * 36}" })
    offer(item(version: 2, minutes: 10))

    Workflow::Library.upgrade_all!

    assert_equal [ 1, 5 ], [ first.reload.library_version, first.live_version.steps.first.dig("config", "minutes") ], "the failed move is rolled back whole"
    assert_equal [ 2, 10 ], [ second.reload.library_version, second.live_version.steps.first.dig("config", "minutes") ]
  end

  test "a following workflow whose steps someone changed stops following and is told of the new version as a copy" do
    offer(item)
    workflow = Workflow.from_library!(item, workspace: @workspace, by: @alice)
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, by: @alice, payload: { "step_id" => "step_wait", "changes" => { "config" => { "minutes" => 1 } } })
    workflow.draft.publish!(by: @alice)
    offer(item(version: 2, minutes: 10))

    Workflow::Library.upgrade_all!

    workflow.reload
    assert_not workflow.follows_library?
    assert_equal 1, workflow.live_version.steps.first.dig("config", "minutes"), "a copy is never changed under the workspace"
    assert_equal 2, workflow.library_update.version
  end

  test "a copy takes a newer version into a draft or keeps its own" do
    offer(item)
    copy = Workflow.from_library!(item, workspace: @workspace, by: @alice, following: false)
    copy.draft.publish!(by: @alice)
    copy.reload
    offer(item(version: 2, minutes: 10))

    assert_equal 2, copy.reload.library_update.version
    copy.keep_own!
    assert_nil copy.reload.library_update

    copy.update!(library_dismissed_version: nil)
    draft = copy.take_library!(by: @alice)
    assert_equal [ 10, "Took Firefight's version 2." ], [ draft.steps.first.dig("config", "minutes"), draft.reason ]
    assert_equal 5, copy.reload.live_version.steps.first.dig("config", "minutes"), "it goes live only when someone publishes it"
    assert_nil copy.library_update

    offer(item(version: 3, minutes: 20))
    error = assert_raises(Workflow::Edit::Refused) { copy.reload.take_library!(by: @alice) }
    assert_equal "Publish or discard the open draft first.", error.message
  end

  test "what changed between two versions reads as sentences" do
    before = definition
    after = definition(minutes: 9, extra: [ { "id" => "step_branch", "name" => "decide", "kind" => DefinedWorkflow::KIND_BRANCH, "config" => {} } ])
    after["edges"] = [ { "from" => "step_wait", "to" => "step_branch" } ]
    after["trigger"] = { "kind" => Workflow::Trigger::KIND_SCHEDULE }

    texts = Workflow::Changes.between(before, after).map(&:text)

    assert_equal [ "It starts on a schedule trigger now.", "Added the step decide (branch).", "Changed its settings of the step wait.",
                   "Connected wait to decide." ], texts
  end

  test "check something later makes a one off draft that reads, judges and posts, ready to publish" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow = Workflow::Library.create!(workspace: @workspace, key: Workflow::Library::KEY_CHECK_LATER, by: @alice,
                                           params: { resource: "web", at: "2026-10-13T14:30", time_zone: "Europe/Belgrade", channel: "#ops" })

      assert_equal "Check web", workflow.name
      assert_nil workflow.library_key
      assert workflow.one_off?
      draft = workflow.draft
      assert_equal %w[status against_normal judge tell], draft.steps.map { |step| step["name"] }
      assert_equal 8, workflow.edits.count
      assert_empty draft.problems
      assert workflow.agent
    end
  end

  test "posting back to the chat it came from needs no channel" do
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow = Workflow::Library.create!(workspace: @workspace, key: Workflow::Library::KEY_CHECK_LATER, by: @alice,
                                           params: { resource: "web", at: "2026-10-13T14:30", time_zone: "UTC", reply_in_chat: true })

      assert_equal true, workflow.draft.steps.last.dig("config", "reply_in_chat")
    end
  end

  test "looking for probing runs every weekday at nine, branches on what the skill found and raises a notice" do
    workflow = Workflow::Library.create!(workspace: @workspace, key: Workflow::Library::KEY_PROBING_SCAN, by: @alice, params: { time_zone: "Europe/Belgrade" })

    draft = workflow.draft
    assert_equal "Every weekday at 09:00 (Europe/Belgrade)", Workflow::Trigger.words(draft.trigger)
    assert_equal %w[scan decide notice], draft.steps.map { |step| step["name"] }
    assert_equal({ "from" => "step_decide", "to" => "step_notice", "route" => "found" }, draft.edges.last)
    assert_empty draft.problems
    refute workflow.all_clear?
  end

  test "reads each connected edge network's security events first when one has a skill for them" do
    edge = Chat::Skill.all.find { |skill| skill.signals.include?(Chat::Skill::SIGNAL_SECURITY_EVENTS) }
    Chat::Skill.stubs(:coverage).returns(stub(skills: [ edge ]))

    draft = Workflow::Library.create!(workspace: @workspace, key: Workflow::Library::KEY_PROBING_SCAN, by: @alice, params: { time_zone: "UTC" }).draft

    assert_equal %w[edge_1 scan decide notice], draft.steps.map { |step| step["name"] }
    assert_equal edge.name, draft.steps.first.dig("config", "skill")
    assert_match "{{steps.edge_1.summary}}", draft.steps.second.dig("config", "focus")
  end

  test "a template refuses what it cannot be made from" do
    assert_raises(Workflow::Library::Refused) { Workflow::Library.create!(workspace: @workspace, key: "nope", by: @alice, params: {}) }
    refused = assert_raises(Workflow::Library::Refused) do
      Workflow::Library.create!(workspace: @workspace, key: Workflow::Library::KEY_CHECK_LATER, by: @alice, params: { resource: "web" })
    end
    assert_equal "Say which channel to post the verdict in.", refused.message
  end
end
