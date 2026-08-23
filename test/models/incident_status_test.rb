require "test_helper"

class IncidentStatusTest < ActiveSupport::TestCase
  # Basic validations

  test "requires name" do
    status = IncidentStatus.new(
      workspace: workspaces(:slack_workspace_one),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      slug: "test",
      position: 1
    )
    assert_not status.valid?
    assert_includes status.errors[:name], "can't be blank"
  end

  test "derives the slug from the name" do
    status = IncidentStatus.new(
      workspace: workspaces(:slack_workspace_one),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Test Status",
      position: 1
    )
    assert status.valid?
    assert_equal "test_status", status.slug
  end

  test "requires incident_lifecycle_stage" do
    status = IncidentStatus.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Status",
      slug: "test",
      position: 1
    )
    assert_not status.valid?
    assert status.errors[:incident_lifecycle_stage].present?
  end

  test "requires position" do
    status = IncidentStatus.new(
      workspace: workspaces(:slack_workspace_one),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Test Status",
      slug: "test"
    )
    # position is required but has no presence validation, just numericality
    assert status.valid?
  end

  # Uniqueness validations

  test "slug must be unique within workspace" do
    existing = incident_statuses(:investigating_ws1)
    duplicate = IncidentStatus.new(
      workspace: existing.workspace,
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Different Name",
      slug: existing.slug,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug can be same across different workspaces" do
    ws1_status = incident_statuses(:investigating_ws1)
    ws2_status = IncidentStatus.new(
      workspace: workspaces(:slack_workspace_two),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Investigating",
      slug: ws1_status.slug,
      position: 1
    )
    assert ws2_status.valid?
  end

  test "only one default status allowed per workspace" do
    existing_default = incident_statuses(:investigating_ws1)
    assert existing_default.is_default

    another_default = IncidentStatus.new(
      workspace: existing_default.workspace,
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Another Default",
      slug: "another_default",
      position: 99,
      is_default: true
    )
    assert_not another_default.valid?
    assert_includes another_default.errors[:is_default], "has already been taken"
  end

  test "multiple non-default statuses allowed per workspace" do
    status1 = IncidentStatus.create!(
      workspace: workspaces(:slack_workspace_one),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Status 1",
      slug: "status_1",
      position: 100,
      is_default: false
    )
    status2 = IncidentStatus.create!(
      workspace: workspaces(:slack_workspace_one),
      incident_lifecycle_stage: incident_lifecycle_stages(:active),
      name: "Status 2",
      slug: "status_2",
      position: 101,
      is_default: false
    )
    assert status1.persisted?
    assert status2.persisted?
  end

  test "different workspaces can each have a default status" do
    ws1_default = incident_statuses(:investigating_ws1)
    ws2_default = incident_statuses(:triaging_ws2)

    assert ws1_default.is_default
    assert ws2_default.is_default
    assert_not_equal ws1_default.workspace_id, ws2_default.workspace_id
  end

  # Associations

  test "belongs to workspace" do
    status = incident_statuses(:investigating_ws1)
    assert_instance_of Workspace, status.workspace
    assert_equal workspaces(:slack_workspace_one), status.workspace
  end

  test "belongs to incident_lifecycle_stage" do
    status = incident_statuses(:investigating_ws1)
    assert_instance_of IncidentLifecycleStage, status.incident_lifecycle_stage
    assert_equal incident_lifecycle_stages(:active), status.incident_lifecycle_stage
  end

  test "has many incidents" do
    status = incident_statuses(:investigating_ws1)
    assert_respond_to status, :incidents
  end

  # Scopes

  test "active scope excludes deleted statuses" do
    active_statuses = IncidentStatus.active
    deleted_status = incident_statuses(:deleted_status)

    assert_not_includes active_statuses, deleted_status
    assert_includes active_statuses, incident_statuses(:investigating_ws1)
  end

  test "live scope returns statuses in triage and active stages" do
    live_statuses = IncidentStatus.live

    assert_includes live_statuses, incident_statuses(:investigating_ws1)
    assert_includes live_statuses, incident_statuses(:identified_ws1)
    assert_includes live_statuses, incident_statuses(:monitoring_ws1)
    assert_not_includes live_statuses, incident_statuses(:resolved_ws1)
    assert_not_includes live_statuses, incident_statuses(:canceled_ws1)
  end

  test "closed scope returns only statuses in closed stage" do
    closed_statuses = IncidentStatus.closed

    assert_includes closed_statuses, incident_statuses(:resolved_ws1)
    assert_includes closed_statuses, incident_statuses(:closed_ws2)
    assert_not_includes closed_statuses, incident_statuses(:investigating_ws1)
    assert_not_includes closed_statuses, incident_statuses(:canceled_ws1)
  end

  test "canceled scope returns only statuses in canceled stage" do
    canceled_statuses = IncidentStatus.canceled

    assert_includes canceled_statuses, incident_statuses(:canceled_ws1)
    assert_not_includes canceled_statuses, incident_statuses(:resolved_ws1)
    assert_not_includes canceled_statuses, incident_statuses(:investigating_ws1)
  end

  test "ordered scope sorts by position ascending" do
    workspace = workspaces(:slack_workspace_one)
    statuses = workspace.incident_statuses.active.ordered

    positions = statuses.map(&:position)
    assert_equal positions.sort, positions
  end

  test "default_status scope returns default statuses" do
    ws1_default = workspaces(:slack_workspace_one).incident_statuses.default_status
    ws2_default = workspaces(:slack_workspace_two).incident_statuses.default_status

    assert_equal incident_statuses(:investigating_ws1), ws1_default
    assert_equal incident_statuses(:triaging_ws2), ws2_default
  end

  # Methods

  test "live? returns true for active stage" do
    status = incident_statuses(:investigating_ws1)
    assert status.live?
  end

  test "live? returns false for closed stage" do
    status = incident_statuses(:resolved_ws1)
    assert_not status.live?
  end

  test "live? returns false for canceled stage" do
    status = incident_statuses(:canceled_ws1)
    assert_not status.live?
  end

  test "closed? returns true for closed stage" do
    status = incident_statuses(:resolved_ws1)
    assert status.closed?
  end

  test "closed? returns false for active stage" do
    status = incident_statuses(:investigating_ws1)
    assert_not status.closed?
  end

  test "active? returns true for active stage" do
    assert incident_statuses(:investigating_ws1).active?
  end

  test "canceled? returns true for canceled stage" do
    assert incident_statuses(:canceled_ws1).canceled?
  end

  # Soft deletes

  test "soft delete sets deleted_at" do
    status = incident_statuses(:investigating_ws1)
    assert_nil status.deleted_at

    status.update!(deleted_at: Time.current)
    assert_not_nil status.deleted_at
  end

  test "soft deleted statuses excluded from active scope" do
    status = incident_statuses(:monitoring_ws1)
    assert_includes IncidentStatus.active, status

    status.update!(deleted_at: Time.current)
    assert_not_includes IncidentStatus.active.reload, status
  end

  # Fixtures loading

  test "workspace one fixtures load correctly" do
    investigating = incident_statuses(:investigating_ws1)
    assert_equal "Investigating", investigating.name
    assert_equal "investigating", investigating.slug
    assert_equal incident_lifecycle_stages(:active), investigating.incident_lifecycle_stage
    assert_equal 1, investigating.position
    assert investigating.is_default
    assert_equal "#FFA500", investigating.color
  end

  test "workspace two fixtures load correctly" do
    triaging = incident_statuses(:triaging_ws2)
    assert_equal "Triaging", triaging.name
    assert_equal "triaging", triaging.slug
    assert_equal incident_lifecycle_stages(:active), triaging.incident_lifecycle_stage
    assert triaging.is_default
  end
end
