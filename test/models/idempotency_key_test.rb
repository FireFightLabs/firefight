require "test_helper"

class IdempotencyKeyTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents, :idempotency_keys

  test "enforces uniqueness of key per workspace and resource_type at DB level" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      IdempotencyKey.create!(
        workspace: workspaces(:slack_workspace_one),
        key: "existing-idempotency-key-123",
        resource_type: "Incident",
        resource_id: SecureRandom.uuid
      )
    end
  end

  test "allows same key for different resource_type" do
    key = IdempotencyKey.create!(
      workspace: workspaces(:slack_workspace_one),
      key: "existing-idempotency-key-123",
      resource_type: "OtherResource",
      resource_id: SecureRandom.uuid
    )
    assert key.persisted?
  end

  test "allows same key in different workspaces" do
    key = IdempotencyKey.create!(
      workspace: workspaces(:slack_workspace_two),
      key: "existing-idempotency-key-123",
      resource_type: "Incident",
      resource_id: SecureRandom.uuid
    )
    assert key.persisted?
  end

  test "stale scope finds keys older than expiry" do
    stale = idempotency_keys(:stale_key)
    assert_includes IdempotencyKey.stale, stale
  end

  test "stale scope excludes recent keys" do
    recent = idempotency_keys(:existing_key)
    assert_not_includes IdempotencyKey.stale, recent
  end
end
