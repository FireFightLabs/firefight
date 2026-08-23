require "test_helper"

class IncidentSeverityTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents

  # Basic validations

  test "requires name" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      slug: "test",
      rank: 1,
      position: 1
    )
    assert_not severity.valid?
    assert_includes severity.errors[:name], "can't be blank"
  end

  test "derives the slug from the name" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      rank: 1,
      position: 1
    )
    assert severity.valid?
    assert_equal "test_severity", severity.slug
  end

  test "rank is assigned on create so it never has to be supplied" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      slug: "test",
      position: 1
    )
    assert severity.valid?
    assert_equal 1, severity.rank
  end

  test "requires position" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      slug: "test",
      rank: 1
    )
    # position is required but has no presence validation, just numericality
    assert severity.valid?
  end

  test "rank must be greater than 0" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      slug: "test",
      rank: 0,
      position: 1
    )
    assert_not severity.valid?
    assert_includes severity.errors[:rank], "must be greater than 0"
  end

  test "rank cannot be negative" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      slug: "test",
      rank: -1,
      position: 1
    )
    assert_not severity.valid?
    assert_includes severity.errors[:rank], "must be greater than 0"
  end

  test "accepts valid rank" do
    severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Test Severity",
      slug: "test_unique",
      rank: 5,
      position: 1
    )
    assert severity.valid?
  end

  # Uniqueness validations

  test "slug must be unique within workspace" do
    existing = incident_severities(:critical_ws1)
    duplicate = IncidentSeverity.new(
      workspace: existing.workspace,
      name: "Different Name",
      slug: existing.slug,
      rank: 1,
      position: 99
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "slug can be same across different workspaces" do
    ws1_severity = incident_severities(:critical_ws1)
    ws2_severity = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_two),
      name: "Critical",
      slug: ws1_severity.slug, # Same slug as workspace one
      rank: 10,
      position: 1
    )
    assert ws2_severity.valid?
  end

  test "only one default severity allowed per workspace" do
    existing_default = incident_severities(:minor_ws1)
    assert existing_default.is_default

    another_default = IncidentSeverity.new(
      workspace: existing_default.workspace,
      name: "Another Default",
      slug: "another_default",
      rank: 2,
      position: 99,
      is_default: true
    )
    assert_not another_default.valid?
    assert_includes another_default.errors[:is_default], "has already been taken"
  end

  test "multiple non-default severities allowed per workspace" do
    severity1 = IncidentSeverity.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "Severity 1",
      slug: "severity_1",
      rank: 6,
      position: 100,
      is_default: false
    )
    severity2 = IncidentSeverity.create!(
      workspace: workspaces(:slack_workspace_one),
      name: "Severity 2",
      slug: "severity_2",
      rank: 8,
      position: 101,
      is_default: false
    )
    assert severity1.persisted?
    assert severity2.persisted?
  end

  test "different workspaces can each have a default severity" do
    ws1_default = incident_severities(:minor_ws1)
    ws2_default = incident_severities(:p1_ws2)

    assert ws1_default.is_default
    assert ws2_default.is_default
    assert_not_equal ws1_default.workspace_id, ws2_default.workspace_id
  end

  # Associations

  test "belongs to workspace" do
    severity = incident_severities(:critical_ws1)
    assert_instance_of Workspace, severity.workspace
    assert_equal workspaces(:slack_workspace_one), severity.workspace
  end

  test "has many incidents" do
    severity = incident_severities(:critical_ws1)
    assert_respond_to severity, :incidents
  end

  # Scopes

  test "active scope excludes deleted severities" do
    active_severities = IncidentSeverity.active
    deleted_severity = incident_severities(:deleted_severity)

    assert_not_includes active_severities, deleted_severity
    assert_includes active_severities, incident_severities(:critical_ws1)
  end

  test "ordered scope sorts by position ascending" do
    workspace = workspaces(:slack_workspace_one)
    severities = workspace.incident_severities.active.ordered

    positions = severities.map(&:position)
    assert_equal positions.sort, positions
  end

  test "by_rank scope sorts by rank descending" do
    workspace = workspaces(:slack_workspace_two)
    severities = workspace.incident_severities.active.by_rank

    ranks = severities.map(&:rank)
    assert_equal ranks.sort.reverse, ranks
  end

  test "default_severity scope returns default severities" do
    ws1_default = workspaces(:slack_workspace_one).incident_severities.default_severity
    ws2_default = workspaces(:slack_workspace_two).incident_severities.default_severity

    assert_equal incident_severities(:minor_ws1), ws1_default
    assert_equal incident_severities(:p1_ws2), ws2_default
  end

  # Default severity

  test "make_default! demotes the incumbent in the same transaction" do
    incumbent = incident_severities(:minor_ws1)
    promoted = incident_severities(:critical_ws1)

    promoted.make_default!

    assert promoted.reload.is_default
    assert_not incumbent.reload.is_default
  end

  test "make_default! leaves other workspaces alone" do
    ws2_default = incident_severities(:p1_ws2)

    incident_severities(:critical_ws1).make_default!

    assert ws2_default.reload.is_default
  end

  test "the database refuses a second default in one workspace" do
    other = incident_severities(:critical_ws1)

    assert_raises(ActiveRecord::RecordNotUnique) do
      IncidentSeverity.where(id: other.id).update_all(is_default: true)
    end
  end

  # Deletability

  test "with_usage_counts attaches the count without an extra query per row" do
    workspace = workspaces(:slack_workspace_one)
    severities = workspace.incident_severities.ordered.with_usage_counts.to_a

    expected = workspace.incidents.group(:incident_severity_id).count
    severities.each do |severity|
      assert_equal expected.fetch(severity.id, 0), severity.usage_count
    end
  end

  test "incident_count falls back to a query when the scope was not applied" do
    severity = incident_severities(:critical_ws1)
    assert_equal severity.incidents.count, severity.usage_count
  end

  test "deletion_blocked_reason names the incident count" do
    severity = incident_severities(:critical_ws1)

    assert_predicate severity.usage_count, :positive?
    assert_match(/in use by #{severity.usage_count} incidents/, severity.deletion_blocked_reason)
  end

  test "deletion_blocked_reason is nil for a severity no incident uses" do
    severity = workspaces(:slack_workspace_one).incident_severities.new(name: "Unused", slug: "unused")
    severity.save_in_position!

    assert_equal 0, severity.usage_count
    assert_nil severity.deletion_blocked_reason
  end

  test "deletion_blocked_reason takes precedence for the default severity" do
    severity = incident_severities(:minor_ws1)
    assert severity.is_default

    assert_match(/default severity/, severity.deletion_blocked_reason)
  end

  test "destroy is blocked by restrict_with_error while incidents reference it" do
    severity = incident_severities(:critical_ws1)

    assert_no_difference -> { IncidentSeverity.count } do
      assert_not severity.destroy
    end
    assert_includes severity.errors[:base], "Cannot delete record because dependent incidents exist"
  end

  # Comparison methods

  test "more_severe_than? returns true when rank is higher" do
    critical = incident_severities(:critical_ws1)
    major = incident_severities(:major_ws1)
    minor = incident_severities(:minor_ws1)

    assert critical.more_severe_than?(major)
    assert critical.more_severe_than?(minor)
    assert major.more_severe_than?(minor)
  end

  test "more_severe_than? returns false when rank is lower" do
    critical = incident_severities(:critical_ws1)
    major = incident_severities(:major_ws1)
    minor = incident_severities(:minor_ws1)

    assert_not minor.more_severe_than?(major)
    assert_not minor.more_severe_than?(critical)
    assert_not major.more_severe_than?(critical)
  end

  test "more_severe_than? returns false when rank is equal" do
    critical = incident_severities(:critical_ws1)
    same_rank = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Same Rank",
      slug: "same_rank",
      rank: critical.rank,
      position: 99
    )

    assert_not critical.more_severe_than?(same_rank)
  end

  test "less_severe_than? returns true when rank is lower" do
    critical = incident_severities(:critical_ws1)
    major = incident_severities(:major_ws1)
    minor = incident_severities(:minor_ws1)

    assert minor.less_severe_than?(major)
    assert minor.less_severe_than?(critical)
    assert major.less_severe_than?(critical)
  end

  test "less_severe_than? returns false when rank is higher" do
    critical = incident_severities(:critical_ws1)
    major = incident_severities(:major_ws1)
    minor = incident_severities(:minor_ws1)

    assert_not critical.less_severe_than?(major)
    assert_not critical.less_severe_than?(minor)
    assert_not major.less_severe_than?(minor)
  end

  test "less_severe_than? returns false when rank is equal" do
    critical = incident_severities(:critical_ws1)
    same_rank = IncidentSeverity.new(
      workspace: workspaces(:slack_workspace_one),
      name: "Same Rank",
      slug: "same_rank",
      rank: critical.rank,
      position: 99
    )

    assert_not critical.less_severe_than?(same_rank)
  end

  # Rank comparisons across different naming conventions

  test "ranks work correctly with different naming conventions" do
    # Workspace one uses: Critical (5), Major (3), Minor (1)
    # Workspace two uses: P0 (10), P1 (7), P2 (4), P3 (1)

    critical_ws1 = incident_severities(:critical_ws1)
    p0_ws2 = incident_severities(:p0_ws2)
    p1_ws2 = incident_severities(:p1_ws2)

    # P0 (rank 10) should be more severe than Critical (rank 5)
    assert p0_ws2.more_severe_than?(critical_ws1)

    # P1 (rank 7) should be more severe than Critical (rank 5)
    assert p1_ws2.more_severe_than?(critical_ws1)
  end

  # Soft deletes

  test "soft delete sets deleted_at" do
    severity = incident_severities(:critical_ws1)
    assert_nil severity.deleted_at

    severity.update!(deleted_at: Time.current)
    assert_not_nil severity.deleted_at
  end

  test "soft deleted severities excluded from active scope" do
    severity = incident_severities(:major_ws1)
    assert_includes IncidentSeverity.active, severity

    severity.update!(deleted_at: Time.current)
    assert_not_includes IncidentSeverity.active.reload, severity
  end

  # Fixtures loading

  test "workspace one fixtures load correctly" do
    critical = incident_severities(:critical_ws1)
    assert_equal "Critical", critical.name
    assert_equal "critical", critical.slug
    assert_equal 5, critical.rank
    assert_equal 1, critical.position
    assert_not critical.is_default
    assert_equal "#DC143C", critical.color

    minor = incident_severities(:minor_ws1)
    assert_equal "Minor", minor.name
    assert_equal 1, minor.rank
    assert minor.is_default
  end

  test "workspace two fixtures load correctly with different naming convention" do
    p0 = incident_severities(:p0_ws2)
    assert_equal "P0", p0.name
    assert_equal "p0", p0.slug
    assert_equal 10, p0.rank
    assert_not p0.is_default

    p1 = incident_severities(:p1_ws2)
    assert_equal "P1", p1.name
    assert_equal 7, p1.rank
    assert p1.is_default
  end
end
