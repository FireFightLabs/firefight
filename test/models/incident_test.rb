require "test_helper"

class IncidentTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_statuses, :incident_severities, :incident_roles, :incidents

  # ============================================================================
  # BASIC VALIDATIONS
  # ============================================================================

  test "requires sequence_number" do
    incident = Incident.new(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      identifier: "INC-999"
    )
    # Skip callbacks and directly set to nil to test validation
    incident.define_singleton_method(:assign_sequence_number) { }
    incident.sequence_number = nil
    assert_not incident.valid?
    assert_includes incident.errors[:sequence_number], "can't be blank"
  end

  test "requires identifier" do
    incident = Incident.new(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      sequence_number: 999
    )
    # Skip callbacks and directly set to nil to test validation
    incident.define_singleton_method(:generate_identifier) { }
    incident.identifier = nil
    assert_not incident.valid?
    assert_includes incident.errors[:identifier], "can't be blank"
  end

  test "requires declared_at" do
    incident = Incident.new(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1)
    )
    # Skip callbacks and directly set to nil to test validation
    incident.define_singleton_method(:set_declared_at) { }
    incident.declared_at = nil
    assert_not incident.valid?
    assert_includes incident.errors[:declared_at], "can't be blank"
  end

  # ============================================================================
  # UNIQUENESS VALIDATIONS
  # ============================================================================

  test "sequence_number must be unique within workspace" do
    existing = incidents(:active_critical_ws1)
    duplicate = Incident.new(
      workspace: existing.workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      sequence_number: existing.sequence_number,
      identifier: "INC-999"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence_number], "has already been taken"
  end

  test "sequence_number can be same across different workspaces" do
    # Use sequence number 5 which exists in ws1 but not in ws2
    ws1_incident = incidents(:manual_incident_ws1)
    assert_equal 5, ws1_incident.sequence_number

    ws2_incident = Incident.new(
      workspace: workspaces(:slack_workspace_two),
      declared_by: workspace_memberships(:alice_workspace_two),
      incident_status: incident_statuses(:triaging_ws2),
      incident_severity: incident_severities(:p0_ws2),
      sequence_number: ws1_incident.sequence_number,
      identifier: "INC-005", # Same identifier format
      declared_at: Time.current
    )
    # Skip callbacks to keep our manually set values
    ws2_incident.define_singleton_method(:assign_sequence_number) { }
    ws2_incident.define_singleton_method(:generate_identifier) { }
    ws2_incident.define_singleton_method(:set_declared_at) { }
    # Should be valid - same sequence_number is OK across workspaces
    assert ws2_incident.valid?, "Expected incident to be valid but got errors: #{ws2_incident.errors.full_messages}"
  end

  test "identifier must be unique within workspace" do
    existing = incidents(:active_critical_ws1)
    duplicate = Incident.new(
      workspace: existing.workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      sequence_number: 999,
      identifier: existing.identifier
    )
    # Skip callback to prevent auto-generation
    duplicate.define_singleton_method(:generate_identifier) { }
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:identifier], "has already been taken"
  end

  test "identifier can be same across different workspaces" do
    ws1_incident = incidents(:active_critical_ws1)
    ws2_incident = Incident.new(
      workspace: workspaces(:slack_workspace_two),
      declared_by: workspace_memberships(:alice_workspace_two),
      incident_status: incident_statuses(:triaging_ws2),
      incident_severity: incident_severities(:p0_ws2),
      sequence_number: 999,
      identifier: ws1_incident.identifier # Same identifier INC-001
    )
    assert ws2_incident.valid?
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "belongs to workspace" do
    incident = incidents(:active_critical_ws1)
    assert_instance_of Workspace, incident.workspace
    assert_equal workspaces(:slack_workspace_one), incident.workspace
  end

  test "belongs to declared_by workspace_membership" do
    incident = incidents(:active_critical_ws1)
    assert_instance_of WorkspaceMembership, incident.declared_by
    assert_equal workspace_memberships(:alice_workspace_one), incident.declared_by
  end

  test "belongs to incident_status" do
    incident = incidents(:active_critical_ws1)
    assert_instance_of IncidentStatus, incident.incident_status
  end

  test "belongs to incident_severity" do
    incident = incidents(:active_critical_ws1)
    assert_instance_of IncidentSeverity, incident.incident_severity
  end

  test "has many incident_events" do
    incident = incidents(:active_critical_ws1)
    assert_respond_to incident, :incident_events
  end

  test "has many incident_actions" do
    incident = incidents(:active_critical_ws1)
    assert_respond_to incident, :incident_actions
  end

  test "has many incident_role_assignments" do
    incident = incidents(:active_critical_ws1)
    assert_respond_to incident, :incident_role_assignments
  end

  test "has many incident_roles through incident_role_assignments" do
    incident = incidents(:active_critical_ws1)
    assert_respond_to incident, :incident_roles
  end

  test "has many assigned_members through incident_role_assignments" do
    incident = incidents(:active_critical_ws1)
    assert_respond_to incident, :assigned_members
  end

  # ============================================================================
  # SCOPES
  # ============================================================================

  test "active scope returns only incidents with live status" do
    active_incidents = Incident.active

    assert_includes active_incidents, incidents(:active_critical_ws1)
    assert_includes active_incidents, incidents(:active_major_ws1)
    assert_includes active_incidents, incidents(:active_p0_ws2)
    assert_not_includes active_incidents, incidents(:resolved_minor_ws1)
    assert_not_includes active_incidents, incidents(:resolved_p2_ws2)
  end

  test "closed scope returns only incidents with closed status" do
    closed_incidents = Incident.closed

    assert_includes closed_incidents, incidents(:resolved_minor_ws1)
    assert_includes closed_incidents, incidents(:resolved_p2_ws2)
    assert_not_includes closed_incidents, incidents(:active_critical_ws1)
    assert_not_includes closed_incidents, incidents(:active_major_ws1)
  end

  test "by_severity scope orders by severity rank descending" do
    workspace = workspaces(:slack_workspace_one)
    incidents_by_severity = workspace.incidents.by_severity.to_a

    # Critical (rank 5) should come before Major (rank 3) which comes before Minor (rank 1)
    critical_incident = incidents(:active_critical_ws1)
    major_incident = incidents(:active_major_ws1)
    minor_incident = incidents(:resolved_minor_ws1)

    critical_index = incidents_by_severity.index(critical_incident)
    major_index = incidents_by_severity.index(major_incident)
    minor_index = incidents_by_severity.index(minor_incident)

    assert critical_index < major_index
    assert major_index < minor_index
  end

  test "recent scope orders by declared_at descending" do
    incidents_recent = Incident.recent.to_a

    declared_times = incidents_recent.map(&:declared_at)
    assert_equal declared_times.sort.reverse, declared_times
  end

  # ============================================================================
  # METHODS
  # ============================================================================

  test "active? returns true for incidents with live status" do
    incident = incidents(:active_critical_ws1)
    assert incident.active?
  end

  test "active? returns false for incidents with closed status" do
    incident = incidents(:resolved_minor_ws1)
    assert_not incident.active?
  end

  test "closed? returns true for incidents with closed status" do
    incident = incidents(:resolved_minor_ws1)
    assert incident.closed?
  end

  test "closed? returns false for incidents with live status" do
    incident = incidents(:active_critical_ws1)
    assert_not incident.closed?
  end

  # ============================================================================
  # CONCERN: SEQUENCING
  # ============================================================================

  test "auto-assigns sequence_number on create" do
    incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Test incident"
    )

    assert_not_nil incident.sequence_number
    assert incident.sequence_number > 0
  end

  test "sequence_number increments from workspace maximum" do
    workspace = workspaces(:slack_workspace_one)
    max_seq = workspace.incidents.maximum(:sequence_number)

    incident = Incident.create!(
      workspace: workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "New incident"
    )

    assert_equal max_seq + 1, incident.sequence_number
  end

  test "sequence_number starts at 1 for workspace with no incidents" do
    workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "New Workspace",
      access_token: "xoxb-test",
      installed_at: Time.current
    )

    # Create required incident status and severity for new workspace
    status = IncidentStatus.create!(
      workspace: workspace,
      name: "Investigating",
      slug: "investigating",
      category: "live",
      position: 1,
      is_default: true
    )
    severity = IncidentSeverity.create!(
      workspace: workspace,
      name: "Minor",
      slug: "minor",
      rank: 1,
      position: 1,
      is_default: true
    )

    incident = Incident.create!(
      workspace: workspace,
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: status,
      incident_severity: severity,
      name: "First incident"
    )

    assert_equal 1, incident.sequence_number
  end

  test "auto-generates identifier from sequence_number" do
    incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Test incident"
    )

    expected_identifier = "INC-#{incident.sequence_number.to_s.rjust(3, '0')}"
    assert_equal expected_identifier, incident.identifier
  end

  test "identifier format is INC-### with leading zeros" do
    incident = incidents(:active_critical_ws1)
    assert_match(/^INC-\d{3}$/, incident.identifier)
  end

  # ============================================================================
  # CONCERN: LIFECYCLE
  # ============================================================================

  test "auto-sets declared_at on create" do
    incident = Incident.new(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Test incident"
    )

    assert_nil incident.declared_at
    incident.save!
    assert_not_nil incident.declared_at
    assert_instance_of ActiveSupport::TimeWithZone, incident.declared_at
  end

  test "does not override declared_at if already set" do
    custom_time = 1.day.ago
    incident = Incident.create!(
      workspace: workspaces(:slack_workspace_one),
      declared_by: workspace_memberships(:alice_workspace_one),
      incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1),
      name: "Test incident",
      declared_at: custom_time
    )

    assert_equal custom_time.to_i, incident.declared_at.to_i
  end

  test "auto-sets resolved_at when status changes to closed" do
    incident = incidents(:active_critical_ws1)
    assert_nil incident.resolved_at

    incident.update!(incident_status: incident_statuses(:resolved_ws1))
    assert_not_nil incident.resolved_at
  end

  test "clears resolved_at when reopening incident" do
    incident = incidents(:resolved_minor_ws1)
    assert_not_nil incident.resolved_at

    incident.update!(incident_status: incident_statuses(:investigating_ws1))
    assert_nil incident.resolved_at
  end

  test "does not change resolved_at when updating other fields" do
    incident = incidents(:resolved_minor_ws1)
    original_resolved_at = incident.resolved_at

    incident.update!(name: "Updated name")
    assert_equal original_resolved_at.to_i, incident.resolved_at.to_i
  end

  test "does not change resolved_at when changing between closed statuses" do
    # Create another closed status first
    another_closed_status = IncidentStatus.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "Completed",
      slug: "completed",
      category: "closed",
      position: 5
    )

    incident = incidents(:resolved_minor_ws1)
    original_resolved_at = incident.resolved_at

    incident.update!(incident_status: another_closed_status)
    assert_equal original_resolved_at.to_i, incident.resolved_at.to_i
  end

  # ============================================================================
  # CONCERN: ROLE MANAGEMENT
  # ============================================================================

  test "lead returns nil when no incident lead assigned" do
    incident = incidents(:active_critical_ws1)
    assert_nil incident.lead
  end

  test "lead= assigns incident lead role" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:bob_workspace_one)

    incident.lead = member
    assert_equal member, incident.lead
  end

  test "lead= updates existing assignment" do
    incident = incidents(:active_critical_ws1)
    alice = workspace_memberships(:alice_workspace_one)
    bob = workspace_memberships(:bob_workspace_one)

    incident.lead = alice
    assert_equal alice, incident.lead

    incident.lead = bob
    assert_equal bob, incident.lead
  end

  test "lead= persists assignment" do
    incident = incidents(:active_critical_ws1)
    member = workspace_memberships(:alice_workspace_one)

    incident.lead = member
    incident.reload

    assert_equal member, incident.lead
  end

  # ============================================================================
  # FIXTURES LOADING
  # ============================================================================

  test "workspace one fixtures load correctly" do
    incident = incidents(:active_critical_ws1)
    assert_equal "INC-001", incident.identifier
    assert_equal 1, incident.sequence_number
    assert_equal "Database connection pool exhausted", incident.name
    assert_not incident.is_private
    assert_not_nil incident.slack_channel_id
    assert_nil incident.resolved_at
  end

  test "resolved incident fixture loads correctly" do
    incident = incidents(:resolved_minor_ws1)
    assert incident.closed?
    assert_not_nil incident.resolved_at
    assert incident.resolved_at < Time.current
  end

  test "private incident fixture loads correctly" do
    incident = incidents(:private_incident_ws1)
    assert incident.is_private
  end

  test "manual incident without Slack channel loads correctly" do
    incident = incidents(:manual_incident_ws1)
    assert_nil incident.slack_channel_id
    assert_nil incident.slack_channel_name
  end

  test "workspace two fixtures use different naming conventions" do
    incident = incidents(:active_p0_ws2)
    assert_equal "P0", incident.incident_severity.name
    assert_equal "Triaging", incident.incident_status.name
  end
end
