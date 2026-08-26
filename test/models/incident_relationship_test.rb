require "test_helper"

class IncidentRelationshipTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident1 = incidents(:active_critical_ws1)
    @incident2 = incidents(:active_major_ws1)
    @incident3 = incidents(:resolved_minor_ws1)
    @member = workspace_memberships(:alice_workspace_one)
  end

  # Validations

  test "requires relationship_type" do
    rel = IncidentRelationship.new(
      incident: @incident1,
      related_incident: @incident2
    )
    assert_not rel.valid?
    assert_includes rel.errors[:relationship_type], "can't be blank"
  end

  test "relationship_type must be valid" do
    rel = IncidentRelationship.new(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: "invalid"
    )
    assert_not rel.valid?
    assert_includes rel.errors[:relationship_type], "is not included in the list"
  end

  # The surfaces show the sentence, the constraint is what makes it true even
  # for a writer that skips validation.
  test "refuses to link an incident to itself" do
    rel = IncidentRelationship.new(
      incident: @incident1,
      related_incident: @incident1,
      relationship_type: IncidentRelationship::RELATED
    )

    assert_not rel.valid?
    assert_includes rel.errors[:related_incident], "must be a different incident"
    assert_raises(ActiveRecord::StatementInvalid) { rel.save(validate: false) }
  end

  test "incidents must be in the same workspace" do
    ws2_incident = incidents(:active_p0_ws2)
    rel = IncidentRelationship.new(
      incident: @incident1,
      related_incident: ws2_incident,
      relationship_type: IncidentRelationship::RELATED
    )
    assert_not rel.valid?
    assert_includes rel.errors[:related_incident], "must belong to the same workspace"
  end

  test "prevents duplicate relationship loop" do
    IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::DUPLICATE
    )

    reverse = IncidentRelationship.new(
      incident: @incident2,
      related_incident: @incident1,
      relationship_type: IncidentRelationship::DUPLICATE
    )
    assert_not reverse.valid?
    assert reverse.errors[:base].any? { |e| e.include?("circular") }
  end

  test "unique pair per type" do
    IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      IncidentRelationship.create!(
        incident: @incident1,
        related_incident: @incident2,
        relationship_type: IncidentRelationship::RELATED
      )
    end
  end

  test "allows same pair with different types" do
    IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )

    rel = IncidentRelationship.new(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::DUPLICATE
    )
    assert rel.valid?
  end

  # Associations

  test "belongs to incident" do
    rel = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED,
      created_by: @member
    )
    assert_equal @incident1, rel.incident
  end

  test "belongs to related_incident" do
    rel = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )
    assert_equal @incident2, rel.related_incident
  end

  test "created_by is optional" do
    rel = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )
    assert_nil rel.created_by
    assert rel.valid?
  end

  # Scopes

  test "related scope filters by type" do
    related = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::RELATED
    )
    duplicate = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident3,
      relationship_type: IncidentRelationship::DUPLICATE
    )

    assert_includes IncidentRelationship.related, related
    assert_not_includes IncidentRelationship.related, duplicate
  end

  test "duplicates scope filters by type" do
    duplicate = IncidentRelationship.create!(
      incident: @incident1,
      related_incident: @incident2,
      relationship_type: IncidentRelationship::DUPLICATE
    )

    assert_includes IncidentRelationship.duplicates, duplicate
  end

  # Constants

  test "RELATIONSHIP_TYPES contains all types" do
    assert_equal %w[duplicate related], IncidentRelationship::RELATIONSHIP_TYPES.sort
  end
end
