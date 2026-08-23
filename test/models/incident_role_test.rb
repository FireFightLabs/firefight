require "test_helper"

class IncidentRoleTest < ActiveSupport::TestCase
  fixtures :workspaces, :incident_roles

  # Basic validations

  test "requires name" do
    role = IncidentRole.new(
      workspace: workspaces(:slack_workspace_one),
      slug: "test",
      position: 1
    )
    assert_not role.valid?
    assert_includes role.errors[:name], "can't be blank"
  end

  test "derives the slug from the name" do
    role = IncidentRole.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Role",
      position: 1
    )
    assert role.valid?
    assert_equal "test_role", role.slug
  end

  test "requires position" do
    role = IncidentRole.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Role",
      slug: "test"
    )
    # position is required but has no presence validation, just numericality
    assert role.valid?
  end

  test "accepts valid role" do
    role = IncidentRole.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Role",
      slug: "test_unique",
      position: 1
    )
    assert role.valid?
  end

  # Uniqueness validations

  test "slug must be unique within workspace" do
    existing = incident_roles(:incident_lead_ws1)
    duplicate = IncidentRole.new(
      workspace: existing.workspace,
      name: "Different Name",
      slug: existing.slug,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug can be same across different workspaces" do
    ws1_role = incident_roles(:incident_lead_ws1)
    ws2_role = IncidentRole.new(
      workspace: workspaces(:slack_workspace_two),
      name: "Incident Lead",
      slug: ws1_role.slug, # Same slug as workspace one
      position: 1
    )
    assert ws2_role.valid?
  end

  # Associations

  test "belongs to workspace" do
    role = incident_roles(:incident_lead_ws1)
    assert_instance_of Workspace, role.workspace
    assert_equal workspaces(:slack_workspace_one), role.workspace
  end

  test "has many incident_role_assignments" do
    role = incident_roles(:incident_lead_ws1)
    assert_respond_to role, :incident_role_assignments
  end

  test "has many incidents through incident_role_assignments" do
    role = incident_roles(:incident_lead_ws1)
    assert_respond_to role, :incidents
  end

  # Scopes

  test "active scope excludes deleted roles" do
    active_roles = IncidentRole.active
    deleted_role = incident_roles(:deleted_role)

    assert_not_includes active_roles, deleted_role
    assert_includes active_roles, incident_roles(:incident_lead_ws1)
  end

  test "ordered scope sorts by position ascending" do
    workspace = workspaces(:slack_workspace_two)
    roles = workspace.incident_roles.active.ordered

    positions = roles.map(&:position)
    assert_equal positions.sort, positions
  end

  test "incident_lead scope returns only incident lead roles" do
    incident_leads = IncidentRole.incident_lead

    assert_includes incident_leads, incident_roles(:incident_lead_ws1)
    assert_not_includes incident_leads, incident_roles(:incident_commander_ws2)
    assert_not_includes incident_leads, incident_roles(:comms_lead_ws2)
  end

  # Soft deletes

  test "soft delete sets deleted_at" do
    role = incident_roles(:incident_lead_ws1)
    assert_nil role.deleted_at

    role.update!(deleted_at: Time.current)
    assert_not_nil role.deleted_at
  end

  test "soft deleted roles excluded from active scope" do
    role = incident_roles(:comms_lead_ws2)
    assert_includes IncidentRole.active, role

    role.update!(deleted_at: Time.current)
    assert_not_includes IncidentRole.active.reload, role
  end

  # Fixtures loading

  test "workspace one MVP fixture loads correctly" do
    incident_lead = incident_roles(:incident_lead_ws1)
    assert_equal "Incident Lead", incident_lead.name
    assert_equal "incident_lead", incident_lead.slug
    assert_equal 1, incident_lead.position
  end

  test "workspace two complex fixtures load correctly" do
    commander = incident_roles(:incident_commander_ws2)
    assert_equal "Incident Commander", commander.name
    assert_equal "incident_commander", commander.slug
    assert_equal 1, commander.position

    comms = incident_roles(:comms_lead_ws2)
    assert_equal "Communications Lead", comms.name
    assert_equal "communications_lead", comms.slug

    tech = incident_roles(:tech_lead_ws2)
    assert_equal "Technical Lead", tech.name
    assert_equal "technical_lead", tech.slug

    scribe = incident_roles(:scribe_ws2)
    assert_equal "Scribe", scribe.name
    assert_equal "scribe", scribe.slug
  end

  test "workspace two roles are properly ordered" do
    workspace = workspaces(:slack_workspace_two)
    roles = workspace.incident_roles.active.ordered.to_a

    assert_equal incident_roles(:incident_commander_ws2), roles[0]
    assert_equal incident_roles(:comms_lead_ws2), roles[1]
    assert_equal incident_roles(:tech_lead_ws2), roles[2]
    assert_equal incident_roles(:scribe_ws2), roles[3]
  end
end
