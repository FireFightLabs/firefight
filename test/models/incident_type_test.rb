require "test_helper"

class IncidentTypeTest < ActiveSupport::TestCase
  # Validations

  test "requires name" do
    type = IncidentType.new(
      workspace: workspaces(:slack_workspace_one),
      slug: "test",
      position: 1
    )
    assert_not type.valid?
    assert_includes type.errors[:name], "can't be blank"
  end

  test "derives the slug from the name" do
    type = IncidentType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      position: 1
    )
    assert type.valid?
    assert_equal "test", type.slug
  end

  test "requires position" do
    type = IncidentType.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test",
      slug: "test"
    )
    assert_not type.valid?
    assert_includes type.errors[:position], "can't be blank"
  end

  test "slug must be unique within workspace" do
    existing = incident_types(:service_outage_ws1)
    duplicate = IncidentType.new(
      workspace: existing.workspace,
      name: "Different Name",
      slug: existing.slug,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug can be same across different workspaces" do
    type = IncidentType.new(
      workspace: workspaces(:slack_workspace_two),
      name: "Service Outage",
      slug: "service_outage",
      position: 1
    )
    assert type.valid?
  end

  # Associations

  test "belongs to workspace" do
    type = incident_types(:service_outage_ws1)
    assert_instance_of Workspace, type.workspace
    assert_equal workspaces(:slack_workspace_one), type.workspace
  end

  test "has many incidents" do
    type = incident_types(:service_outage_ws1)
    assert_respond_to type, :incidents
  end

  # Scopes

  test "active scope excludes deleted types" do
    active_types = IncidentType.active
    assert_not_includes active_types, incident_types(:deleted_type)
    assert_includes active_types, incident_types(:service_outage_ws1)
  end

  test "ordered scope sorts by position" do
    workspace = workspaces(:slack_workspace_one)
    types = workspace.incident_types.active.ordered
    positions = types.map(&:position)
    assert_equal positions.sort, positions
  end

  # Soft deletes

  test "soft delete sets deleted_at" do
    type = incident_types(:service_outage_ws1)
    assert_nil type.deleted_at

    type.update!(deleted_at: Time.current)
    assert_not_nil type.deleted_at
  end

  test "soft deleted types excluded from active scope" do
    type = incident_types(:performance_degradation_ws1)
    assert_includes IncidentType.active, type

    type.update!(deleted_at: Time.current)
    assert_not_includes IncidentType.active.reload, type
  end

  # Fixtures

  test "workspace one fixtures load correctly" do
    outage = incident_types(:service_outage_ws1)
    assert_equal "Service Outage", outage.name
    assert_equal "service_outage", outage.slug
    assert_equal 1, outage.position
  end

  test "workspace two fixture loads correctly" do
    outage = incident_types(:outage_ws2)
    assert_equal "Outage", outage.name
    assert_equal workspaces(:slack_workspace_two), outage.workspace
  end
end
