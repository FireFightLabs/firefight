require "test_helper"

class IncidentTranscriptMessageTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  test "belongs to workspace, incident, and optional membership" do
    message = build_message
    assert_equal @workspace, message.workspace
    assert_equal @incident, message.incident
    assert_equal @member, message.workspace_membership
  end

  test "workspace_membership is optional" do
    message = build_message(workspace_membership: nil)
    assert message.save
  end

  test "content round-trips through encryption" do
    message = build_message(content: "investigating db replica lag").tap(&:save!)
    assert_equal "investigating db replica lag", message.reload.content
  end

  test "raw DB column stores ciphertext, not plaintext" do
    message = build_message(content: "ssh into prod-3 and tail logs").tap(&:save!)

    raw = IncidentTranscriptMessage.connection.select_value(
      "SELECT content FROM incident_transcript_messages WHERE id = '#{message.id}'"
    )

    assert_not_equal "ssh into prod-3 and tail logs", raw
    assert_match(/\A\{.*\}\z/, raw, "expected AR::Encryption JSON envelope")
  end

  test "kept scope excludes soft-deleted rows" do
    kept = build_message(slack_ts: "1.001").tap(&:save!)
    build_message(slack_ts: "1.002", deleted_at: Time.current).tap(&:save!)

    assert_includes IncidentTranscriptMessage.kept, kept
    assert_equal 1, IncidentTranscriptMessage.kept.count
  end

  test "scrubbed defaults to false" do
    assert_equal false, build_message.tap(&:save!).reload.scrubbed
  end

  test "requires workspace, incident, slack_ts, slack_user_id, content, posted_at" do
    message = IncidentTranscriptMessage.new
    assert_not message.valid?
    %i[workspace incident slack_ts slack_user_id content posted_at].each do |field|
      assert message.errors[field].any?, "expected presence error on #{field}"
    end
  end

  private

  def build_message(**overrides)
    IncidentTranscriptMessage.new({
      workspace: @workspace,
      incident: @incident,
      workspace_membership: @member,
      slack_ts: "1717420800.000100",
      slack_user_id: "U_TEST",
      content: "hello world",
      posted_at: Time.current
    }.merge(overrides))
  end
end
