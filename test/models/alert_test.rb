require "test_helper"

class AlertTest < ActiveSupport::TestCase
  fixtures :workspaces

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @source = AlertSource.create!(workspace: @workspace, name: "Test source", provider: AlertSource::PROVIDER_GENERIC)
  end

  test "fallback fingerprint is deterministic over source, service and title" do
    fields = { "service" => "api", "title" => "DB down" }

    assert_equal Alert.fallback_fingerprint(@source, fields), Alert.fallback_fingerprint(@source, fields)
    assert_not_equal Alert.fallback_fingerprint(@source, fields),
                     Alert.fallback_fingerprint(@source, fields.merge("title" => "Other"))
  end

  test "record_firing! bumps the counter and reopens a resolved alert" do
    alert = @source.alerts.create!(
      workspace: @workspace, external_id: "e1", fingerprint: "f1",
      status: Alert::STATUS_RESOLVED, resolved_at: 1.minute.ago,
      received_at: 5.minutes.ago, last_seen_at: 5.minutes.ago
    )

    alert.record_firing!

    assert_equal 2, alert.event_count
    assert alert.firing?
    assert_nil alert.resolved_at
  end

  test "resolve! stamps resolved_at and status" do
    alert = @source.alerts.create!(
      workspace: @workspace, external_id: "e2", fingerprint: "f2",
      received_at: Time.current, last_seen_at: Time.current
    )

    alert.resolve!

    assert_equal Alert::STATUS_RESOLVED, alert.status
    assert alert.resolved_at.present?
  end
end
