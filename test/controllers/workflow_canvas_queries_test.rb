require "test_helper"

# What a workflow's canvas costs the database. The page polls itself while it is open, reloading the canvas's props, and
# the run's too while a run is open, so neither may cost more for more tools, connections or runs, and neither builds the
# tools list, which reads every connection's schemas and is only the palette's, sent once and deferred.
class WorkflowCanvasQueriesTest < ActionDispatch::IntegrationTest
  include ManyToolsHelper

  # The props the page's polls ask for, as CANVAS_VISIT and RUN_VISIT name them (pages/halon/hooks/use-workflow-edits.ts).
  P = WorkflowCanvasController
  CANVAS_POLL = [ P::PROP_WORKFLOW, P::PROP_DOCUMENT, P::PROP_VERSIONS, P::PROP_SUGGESTIONS, P::PROP_HALON_CHANGES,
                  P::PROP_PUBLISH_REQUESTS, P::PROP_MY_PUBLISH_REQUEST ].freeze
  RUN_POLL = [ *CANVAS_POLL, P::PROP_RUN, P::PROP_RUNS, P::PROP_LAST_RUN ].freeze
  # Pinned, so a query added per prop, step, tool or run shows here. Raise them only for a prop that is new.
  PAGE_QUERIES = 61
  CANVAS_POLL_QUERIES = 27
  RUN_POLL_QUERIES = 35

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

  # A request reads its workspace afresh, as each one in production does.
  def sent(path, props)
    sign_in(users(:alice), Workspace.find(@workspace.id))
    headers = props ? inertia_partial_headers("halon/workflow", props) : inertia_headers
    queries_sent { get path, headers: headers }.tap { assert_response :success }
  end
end
