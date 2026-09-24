require "test_helper"

class Investigation::RehearsalTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @original = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      seed_pack: { "incident" => { "identifier" => @incident.identifier } }, status: Investigation::STATUS_SUCCEEDED
    )
    @changes = recorded("github.changes_before", { "at" => "2026-09-24T08:45:47Z" }, "Suspects ranked")
    @original.update!(chat: Chat.open!(owner: @original, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "claude-sonnet-4-5", provider: "anthropic")))
    @first_read = recorded("github.fetch_file", { "repo" => "acme/cloud", "path" => "a.rb" }, "first read")
    @second_read = recorded("github.fetch_file", { "repo" => "acme/cloud", "path" => "a.rb" }, "second read")
    @refused = recorded("github.blame", { "repo" => "acme/cloud" }, nil, failed: "Denied")
  end

  test "a replay answers each call with what the run recorded for it, in the order it was made" do
    replay = replay_of_original

    assert_equal "first read", call(replay, "github.fetch_file", "repo" => "acme/cloud", "path" => "a.rb").value
    assert_equal "second read", call(replay, "github.fetch_file", "repo" => "acme/cloud", "path" => "a.rb").value
    assert_equal "github.blame failed: Denied", call(replay, "github.blame", "repo" => "acme/cloud").value
    assert_equal Investigation::Step::STATUS_FAILED, replay.steps.find_by!(action_key: "github.blame").status
  end

  test "a call the run never made is answered as not recorded, and never reaches anything" do
    replay = replay_of_original
    Chat::ToolCall.expects(:run!).never

    outcome = call(replay, "github.fetch_file", "repo" => "acme/cloud", "path" => "b.rb")

    assert_equal Investigation::ToolCall::NOT_RECORDED, outcome.value
    assert_equal 1, Investigation::Rehearsal.summarize(replay).not_recorded
  end

  test "a replay starts from the same facts and the steps taken before the loop, then runs quietly on the model given" do
    Investigation::Runner.any_instance.stubs(:run).returns(Investigation::Runner::Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil))

    result = Investigation::Rehearsal.replay!(@original, model: "gpt-5-mini", provider: "openai")

    replay = result.investigation
    assert replay.rehearsal?
    assert_equal @original, replay.replay_of
    assert_equal @original.seed_pack, replay.seed_pack
    assert_equal [ [ 1, "Suspects ranked" ] ], replay.steps.map { |step| [ step.position, step.raw_result ] }
    assert_equal "gpt-5-mini", replay.model_override
    assert_equal Investigation::STATUS_SUCCEEDED, replay.status
  end

  test "a rehearsal never holds the incident's one live run" do
    @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)

    assert_nothing_raised do
      @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true, max_turns: 10, max_spend_cents: 400)
    end
    assert_equal 1, Investigation.where(subject: @incident).live.seen.count
  end

  test "a rehearsal is never handed to a worker, read back as the incident's run, or kept as a past answer" do
    rehearsal = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true, max_turns: 10, max_spend_cents: 400,
      created_at: 1.hour.ago
    )
    finding = rehearsal.conclude!(summary: "It was the database")

    assert_not_includes Investigation.abandoned, rehearsal
    assert_not finding.search_embeddable?
    assert_not_includes @incident.investigations.seen, rehearsal
  end

  test "a bench finding is scored on naming every expected text, whatever its case" do
    result = Investigation::Rehearsal::Result.new(
      investigation: nil, model: nil, status: nil, summary: "The billing controller calls require_admin!, which nothing defines",
      cause: nil, claims: [ "Every signed in visit raises NoMethodError" ], turns: 0, spent_cents: 0, steps: 0, not_recorded: 0, seconds: nil
    )

    assert result.names?([ "REQUIRE_ADMIN!", "nomethoderror" ])
    assert_not result.names?([ "require_admin!", "database" ])
  end

  private

  def replay_of_original
    @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true, replay_of: @original,
      max_turns: 10, max_spend_cents: 400
    )
  end

  def call(run, action_key, params) = run.tool_call(action_key: action_key, params: params, tool_name: action_key.tr(".", "_"))

  def recorded(action_key, params, text, failed: nil)
    step = @original.steps.create!(
      position: @original.next_step_position, action_key: action_key, params: params, tool_name: action_key.tr(".", "_"),
      status: Investigation::Step::STATUS_RUNNING
    )
    failed ? step.fail!(failed) : step.succeed!(compacted_result: text, raw_result: text)
    step
  end
end
