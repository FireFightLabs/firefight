require "test_helper"

class IncidentLifecycleStageTest < ActiveSupport::TestCase
  fixtures :incident_lifecycle_stages, :incident_statuses, :workspaces

  # ============================================================================
  # VALIDATIONS
  # ============================================================================

  test "requires key" do
    stage = IncidentLifecycleStage.new(name: "Test", description: "desc", position: 99)
    assert_not stage.valid?
    assert_includes stage.errors[:key], "can't be blank"
  end

  test "key must be unique" do
    stage = IncidentLifecycleStage.new(key: "active", name: "Dup", description: "desc", position: 99)
    assert_not stage.valid?
    assert_includes stage.errors[:key], "has already been taken"
  end

  test "key must be in KEYS" do
    stage = IncidentLifecycleStage.new(key: "invalid", name: "Test", description: "desc", position: 99)
    assert_not stage.valid?
    assert_includes stage.errors[:key], "is not included in the list"
  end

  test "requires name" do
    stage = IncidentLifecycleStage.new(key: "triage", description: "desc", position: 99)
    assert_not stage.valid?
    assert_includes stage.errors[:name], "can't be blank"
  end

  test "requires description" do
    stage = IncidentLifecycleStage.new(key: "triage", name: "Test", position: 99)
    assert_not stage.valid?
    assert_includes stage.errors[:description], "can't be blank"
  end

  test "requires position" do
    stage = IncidentLifecycleStage.new(key: "triage", name: "Test", description: "desc")
    assert_not stage.valid?
    assert_includes stage.errors[:position], "can't be blank"
  end

  # ============================================================================
  # PREDICATES
  # ============================================================================

  test "triage? returns true for triage stage" do
    assert incident_lifecycle_stages(:triage).triage?
    assert_not incident_lifecycle_stages(:active).triage?
  end

  test "active? returns true for active stage" do
    assert incident_lifecycle_stages(:active).active?
    assert_not incident_lifecycle_stages(:closed).active?
  end

  test "closed? returns true for closed stage" do
    assert incident_lifecycle_stages(:closed).closed?
    assert_not incident_lifecycle_stages(:active).closed?
  end

  test "canceled? returns true for canceled stage" do
    assert incident_lifecycle_stages(:canceled).canceled?
    assert_not incident_lifecycle_stages(:closed).canceled?
  end

  test "open? returns true for triage and active stages" do
    assert incident_lifecycle_stages(:triage).open?
    assert incident_lifecycle_stages(:active).open?
    assert_not incident_lifecycle_stages(:closed).open?
    assert_not incident_lifecycle_stages(:canceled).open?
  end

  # ============================================================================
  # CONSTANTS
  # ============================================================================

  test "KEYS contains all four stages" do
    assert_equal %w[active canceled closed triage], IncidentLifecycleStage::KEYS.sort
  end

  # ============================================================================
  # ASSOCIATIONS
  # ============================================================================

  test "has many incident_statuses" do
    active_stage = incident_lifecycle_stages(:active)
    assert_includes active_stage.incident_statuses, incident_statuses(:investigating_ws1)
  end

  # ============================================================================
  # FIXTURES
  # ============================================================================

  test "all four stages exist" do
    assert_equal 4, IncidentLifecycleStage.count
    assert_not_nil IncidentLifecycleStage.find_by(key: "triage")
    assert_not_nil IncidentLifecycleStage.find_by(key: "active")
    assert_not_nil IncidentLifecycleStage.find_by(key: "closed")
    assert_not_nil IncidentLifecycleStage.find_by(key: "canceled")
  end

  test "stages are ordered by position" do
    stages = IncidentLifecycleStage.ordered
    assert_equal %w[triage active closed canceled], stages.map(&:key)
  end
end
