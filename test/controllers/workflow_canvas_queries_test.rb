require "test_helper"

# What a workflow's canvas costs the database. The page polls itself while it is open, reloading the canvas's props, and
# the run's too while a run is open, so neither may cost more for more tools, connections or runs, and neither builds the
# tools list, which reads every connection's schemas and is only the palette's, sent once and deferred.
class WorkflowCanvasQueriesTest < ActionDispatch::IntegrationTest
  include ManyToolsHelper

  # The props the page's polls ask for, as CANVAS_VISIT and RUN_VISIT name them (pages/halon/hooks/use-workflow-edits.ts).
  CANVAS = WorkflowCanvasController
  CANVAS_POLL = [ CANVAS::PROP_WORKFLOW, CANVAS::PROP_DOCUMENT, CANVAS::PROP_VERSIONS, CANVAS::PROP_SUGGESTIONS, CANVAS::PROP_HALON_CHANGES,
                  CANVAS::PROP_PUBLISH_REQUESTS, CANVAS::PROP_MY_PUBLISH_REQUEST ].freeze
  RUN_POLL = [ *CANVAS_POLL, CANVAS::PROP_RUN, CANVAS::PROP_RUNS, CANVAS::PROP_LAST_RUN ].freeze
  # Pinned, so a query added per prop, step, tool or run shows here. Raise them only for a prop that is new.
  PAGE_QUERIES = 62
  CANVAS_POLL_QUERIES = 28
  RUN_POLL_QUERIES = 36

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    # Cached as in production, so what a request reads of the connections' tools is kept for the next.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    connection_with_tools(@workspace, 3, name: "Ops")
    @workflow = Workflow.create!(workspace: @workspace, name: "Rerun failed CI")
    2.times do
      @workflow.reload.open_draft!(by: @alice).update!(steps: steps, edges: edges)
      @workflow.reload.draft.publish!(by: @alice)
    end
    @workflow.reload
    sign_in(users(:alice), @workspace)
  end

  test "the page and both polls cost the pinned queries, and none of them builds the tools list" do
    run = runs(2).first
    Chat::Tools::Choices.expects(:tools).never

    page, canvas_poll, run_poll = costs(run)
    assert_equal PAGE_QUERIES, page.size, repeated_queries(page)
    assert_equal CANVAS_POLL_QUERIES, canvas_poll.size, repeated_queries(canvas_poll)
    assert_equal RUN_POLL_QUERIES, run_poll.size, repeated_queries(run_poll)
  end

  test "more connections, tools and runs cost the page and both polls nothing more" do
    runs(2)
    few = costs(@workflow.runs.newest_first.first)
    3.times { |index| connection_with_tools(@workspace, 40, name: "More #{index}") }
    many = costs(runs(30).first)

    few.zip(many).each { |few_sent, many_sent| assert_same_queries(few_sent, many_sent) }
  end

  test "a visit works out each step's reach once, though the header and the steps both show it" do
    worked_out = []
    DefinedWorkflow::Reach.stubs(:reach_for_tool).with { |_workspace, name, arguments| worked_out << [ name, arguments.to_h ] }.returns([])

    sent(workflow_path(@workflow), nil)

    assert_equal [ [ "ops_tool_0", { "service" => "web" } ], [ "ops_tool_2", { "service" => "web" } ], [ "ops_tool_1", { "service" => "web" } ],
                   [ "ops_tool_0", {} ] ].sort_by(&:to_s), worked_out.sort_by(&:to_s)
  end

  test "the tools list costs no more for more tools, and words what each set of grants needs once" do
    sent(workflow_path(@workflow), [ CANVAS::PROP_TOOLS ])
    few = sent(workflow_path(@workflow), [ CANVAS::PROP_TOOLS ])
    ops = @workspace.integrations.find_by!(name: "Ops")
    40.times do |index|
      ops.tools.create!(name: "more_#{index}", description: "Does more #{index}", read_only: true, enabled: true,
                        params_schema: { "type" => "object", "properties" => { "service" => { "type" => "string" } } })
    end

    sent(workflow_path(@workflow), [ CANVAS::PROP_TOOLS ])
    many = sent(workflow_path(@workflow), [ CANVAS::PROP_TOOLS ])
    assert_same_queries(few, many)

    worded = Hash.new(0)
    Workflow.any_instance.stubs(:grant_sentence).with { |needs| worded[needs.map(&:key)] += 1 }.returns(nil)
    sent(workflow_path(@workflow), [ CANVAS::PROP_TOOLS ])
    assert_operator inertia_props[CANVAS::PROP_TOOLS].size, :>, worded.size
    assert_equal [ 1 ], worded.values.uniq
  end

  private

  def steps
    [
      call("list", "ops_tool_0"), call("look", "ops_tool_2"), call("rerun", "ops_tool_1").deep_merge("config" => { "undo" => "Cancel the run by hand." }),
      { "id" => "wait", "name" => "wait_for_ci", "kind" => DefinedWorkflow::Steps::Watch.kind,
        "config" => { "title" => "CI", "minutes" => 30, "steps" => [ { "label" => "CI", "tool" => "ops_tool_0", "arguments" => {}, "goal" => "Green" } ] } }
    ]
  end

  def call(id, tool) = { "id" => id, "name" => id, "kind" => Workflow::StepKinds::KIND_CALL_TOOL, "config" => { "tool" => tool, "arguments" => { "service" => "web" } } }

  def edges = [ { "from" => "list", "to" => "look" }, { "from" => "look", "to" => "rerun" }, { "from" => "rerun", "to" => "wait" } ]

  # Runs of the live version, newest first, each with a row for every step.
  def runs(count)
    Array.new(count) do |index|
      run = @workflow.runs.create!(workspace: @workspace, version: @workflow.live_version, status: Workflow::Run::STATUS_SUCCEEDED,
                                   trigger_kind: Workflow::Trigger::KIND_MANUAL, started_by_kind: Workflow::Run::STARTED_BY_PERSON,
                                   started_by: @alice, start_key: SecureRandom.uuid, started_at: index.minutes.ago, finished_at: index.minutes.ago)
      steps.each { |step| run.steps.create!(step_key: step["id"], name: step["name"], kind: step["kind"], status: DefinedWorkflow::STEP_SUCCEEDED, output: { "ok" => true }) }
      run
    end.sort_by(&:created_at).reverse
  end

  # Each counted once the cache holds what the visit before kept, as on a page open a while.
  def costs(run)
    sent(workflow_path(@workflow), nil)
    [ sent(workflow_path(@workflow), nil), sent(workflow_path(@workflow), CANVAS_POLL), sent(workflow_path(@workflow, run: run.id), RUN_POLL) ]
  end

  def sent(path, props)
    headers = props ? inertia_partial_headers("halon/workflow", props) : inertia_headers
    queries_sent { get path, headers: headers }.tap { assert_response :success }
  end
end
