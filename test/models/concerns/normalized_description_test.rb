require "test_helper"

class NormalizedDescriptionTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities

  def build_severity(description)
    workspace = workspaces(:slack_workspace_one)
    workspace.incident_severities.new(
      name: "Test",
      slug: "test-#{SecureRandom.hex(4)}",
      rank: 1,
      position: workspace.incident_severities.maximum(:position).to_i + 1,
      description: description
    )
  end

  test "capitalizes an all-lowercase first word and terminates the sentence" do
    severity = build_severity("limited impact or workaround available")
    severity.validate

    assert_equal "Limited impact or workaround available.", severity.description
  end

  test "leaves a first word that carries its own capitalization alone" do
    assert_equal "iOS checkout is broken.", IncidentSeverity.normalize_description("iOS checkout is broken")
    assert_equal "eBay integration is down.", IncidentSeverity.normalize_description("eBay integration is down")
  end

  test "does not double up an existing terminator" do
    assert_equal "Already a sentence.", IncidentSeverity.normalize_description("Already a sentence.")
    assert_equal "Is checkout down?", IncidentSeverity.normalize_description("Is checkout down?")
    assert_equal "Everything is on fire!", IncidentSeverity.normalize_description("Everything is on fire!")
  end

  test "trims surrounding whitespace" do
    assert_equal "Padded out.", IncidentSeverity.normalize_description("  padded out  ")
  end

  test "leaves blank descriptions untouched" do
    severity = build_severity(nil)
    severity.validate

    assert_nil severity.description
  end

  test "applies on update as well as create" do
    severity = build_severity("first version")
    severity.save!

    severity.update!(description: "second version")

    assert_equal "Second version.", severity.reload.description
  end

  test "covers every option list that renders a description" do
    workspace = workspaces(:slack_workspace_one)

    status = workspace.incident_statuses.create!(
      name: "Probing", slug: "probing", position: 90,
      incident_lifecycle_stage: incident_lifecycle_stages(:triage),
      description: "still working out what happened"
    )
    type = workspace.incident_types.create!(
      name: "Probe", slug: "probe", position: 91, description: "a probe type"
    )
    role = workspace.incident_roles.create!(
      name: "Scribe", slug: "scribe", position: 92, description: "takes notes"
    )
    field = workspace.incident_field_definitions.create!(
      slug: "probe_field", name: "Probe Field", field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE, position: 93,
      description: "which area is affected"
    )

    assert_equal "Still working out what happened.", status.description
    assert_equal "A probe type.", type.description
    assert_equal "Takes notes.", role.description
    assert_equal "Which area is affected.", field.description
  end
end
