require "test_helper"

class IncidentSummaryTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "belongs to incident, workspace, and optionally inference" do
    summary = build_summary.tap(&:save!)
    assert_equal @incident, summary.incident
    assert_equal @workspace, summary.workspace
    assert_nil summary.inference
  end

  test "content round-trips through encryption" do
    summary = build_summary(content: "team investigating db replica lag").tap(&:save!)
    assert_equal "team investigating db replica lag", summary.reload.content
  end

  test "raw DB column stores ciphertext, not plaintext" do
    summary = build_summary(content: "rolled back deploy 4f2a").tap(&:save!)

    raw = IncidentSummary.connection.select_value(
      "SELECT content FROM incident_summaries WHERE id = '#{summary.id}'"
    )

    assert_not_equal "rolled back deploy 4f2a", raw
    assert_match(/\A\{.*\}\z/, raw, "expected AR::Encryption JSON envelope")
  end

  test "requires content, summary_up_to_ts, generated_at, model" do
    summary = IncidentSummary.new(incident: @incident, workspace: @workspace)
    assert_not summary.valid?
    %i[content summary_up_to_ts generated_at model].each do |field|
      assert summary.errors[field].any?, "expected presence error on #{field}"
    end
  end

  test "one summary per incident is enforced at the DB level" do
    build_summary.save!

    duplicate = build_summary
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  private

  def build_summary(**overrides)
    IncidentSummary.new({
      incident: @incident,
      workspace: @workspace,
      content: "investigation in progress",
      summary_up_to_ts: "1717420800.000100",
      generated_at: Time.current,
      model: "claude-haiku-4-5"
    }.merge(overrides))
  end
end
