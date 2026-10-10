require "test_helper"

class Investigation::CheckToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @check = @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                                     hour: 9, time_zone: "UTC")
    @run = @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)
    @step = @run.steps.create!(position: 1, tool_name: "query_metrics", label: "Metrics of orders-db", action_key: "northflank.query_metrics",
                               status: Investigation::Step::STATUS_SUCCEEDED, started_at: Time.current)
    @disk = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_DATABASE,
                                          external_id: "orders-db-id", name: "orders-db", first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def note(**arguments)
    Investigation::Tools::NoteProblem.new(@run).call(
      "signal" => "disk", "topic" => "orders-db volume", "summary" => "It is full around Oct 28.", "severity" => "medium", "steps" => [ 1 ], **arguments
    )
  end

  test "a scheduled check is handed note_problem and finish_check, not an investigation's theories and conclusion" do
    names = Investigation::Tools.own_tools(@run).map(&:name)

    assert_equal %w[note_problem finish_check], names
  end

  test "a problem is kept with its resource on the map and its date, against the check and the run" do
    assert_match "Noted.", note("resource" => "orders-db", "due_on" => "2026-10-28")

    notice = @workspace.investigation_notices.sole
    assert_equal [ @disk, Date.new(2026, 10, 28), @check, @run ], [ notice.resource, notice.due_on, notice.check, notice.investigation ]
    assert notice.unsaid
  end

  test "a problem needs a real step behind it, a resource on the map and a real date" do
    assert_match "cites step 9", note("steps" => [ 9 ])[:error]
    assert_match "Nothing on the resource map is called nowhere", note("resource" => "nowhere")[:error]
    assert_match "is not a date", note("due_on" => "soon")[:error]
    assert_empty @workspace.investigation_notices
  end

  test "finish_check records the run's answer, which ends it" do
    Investigation::Tools::FinishCheck.new(@run).call("summary" => "Read 4 disks. orders-db fills by Oct 28.")

    assert_equal "Read 4 disks. orders-db fills by Oct 28.", @run.reload.finding.summary
  end

  test "a scheduled check's answer is not offered to similarity search" do
    @run.conclude!(summary: "Read 4 disks.")

    assert_not @run.finding.search_embeddable?
  end

  # Stands in for the engine, so the run's bookkeeping is tested without calling a model.
  class FakeMonitor
    attr_reader :tool_names

    def initialize(run) = @run = run

    def run(**arguments)
      @tool_names = arguments[:tools].map(&:name)
      @run.conclude!(summary: "Read 4 disks.")
      FirefightAi::AgentLoop::Outcome.new(status: :answered, turns_used: 1, spent_micros: 0)
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")
  end

  test "a scheduled check runs on the monitoring prompts and says only news" do
    @run.claim!
    monitor = FakeMonitor.new(@run)
    FirefightAi::Monitor.expects(:new).with(@workspace, inferable: @run, model: anything).returns(monitor)
    FirefightAi::Investigator.expects(:new).never
    Investigation::CheckDelivery.any_instance.expects(:answered!)

    assert_equal Investigation::STATUS_SUCCEEDED, Investigation::Runner.new(@run).run.status
    assert_includes monitor.tool_names, "note_problem"
    assert_not_includes monitor.tool_names, "conclude"
  end
end
