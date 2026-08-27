require "test_helper"

class IncidentFormPromptTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
  end

  test "asks exactly what the resolver resolves, in the same order" do
    expected = IncidentFormResolver.new(@workspace)
      .resolve(IncidentForm::SLUG_UPDATE, context: IncidentConditionEvaluator.context_for(@incident))
      .map { |field| field.system_field_key || field.incident_field_definition.slug }

    assert_equal expected, fields(IncidentForm::SLUG_UPDATE).map(&:key)
  end

  test "a resolve offers only closed statuses, so nothing resolves into Investigating" do
    add_closed_status

    status = field(IncidentForm::SLUG_RESOLVE, IncidentSystemField::KEY_STATUS)

    assert status, "expected the resolve form to ask for a status once there are two"
    stages = @workspace.incident_statuses.where(slug: status.choices.map(&:value))
      .map { |record| record.incident_lifecycle_stage.key }
    assert_equal [ IncidentLifecycleStage::CLOSED ], stages.uniq
  end

  test "an update offers every active status" do
    status = field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_STATUS)

    assert_equal @workspace.incident_statuses.active.count, status.choices.size
  end

  test "severity and status prefill from the incident" do
    severity = field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_SEVERITY)
    status = field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_STATUS)

    assert_equal @incident.incident_severity.slug, severity.value
    assert_equal @incident.incident_status.slug, status.value
  end

  test "the lead is picked from the roster by id, not by platform user id" do
    add_closed_status
    lead = field(IncidentForm::SLUG_RESOLVE, IncidentSystemField::KEY_LEAD)

    assert_equal IncidentFormPrompt::INPUT_PERSON, lead.input
    assert_equal @workspace.workspace_memberships.count, lead.choices.size
    assert_includes lead.choices.map(&:value), workspace_memberships(:alice_workspace_one).id
  end

  test "the fixed choices come from the registry both surfaces read" do
    next_update = field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_NEXT_UPDATE)

    assert_equal IncidentSystemField::NEXT_UPDATE_CHOICES.map(&:value), next_update.choices.map(&:value)
    assert_equal IncidentSystemField::DEFAULT_NEXT_UPDATE_MINUTES, next_update.value
  end

  # The resolver drops Next Update once the picked status ends the incident.
  # The prompt has to re-ask it rather than deciding for itself.
  test "picking a terminal status drops the next update question" do
    assert field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_NEXT_UPDATE)

    terminal = @workspace.incident_statuses.terminal.active.first
    asked = fields(IncidentForm::SLUG_UPDATE, answers: { "status" => terminal.slug }).map(&:key)

    assert_not_includes asked, IncidentSystemField::KEY_NEXT_UPDATE
  end

  test "an answer already given wins over what the incident holds" do
    other = @workspace.incident_severities.active.where.not(id: @incident.incident_severity_id).first
    severity = field(IncidentForm::SLUG_UPDATE, IncidentSystemField::KEY_SEVERITY, answers: { "severity" => other.slug })

    assert_equal other.slug, severity.value
  end

  test "every field names an input the dashboard knows how to render" do
    IncidentForm::SLUGS.excluding(IncidentForm::SLUG_DECLARE).each do |slug|
      fields(slug).each do |field|
        assert_includes IncidentFormPrompt::INPUTS, field.input, "#{slug}/#{field.key}"
      end
    end
  end

  private

  def add_closed_status
    @workspace.incident_statuses.create!(
      name: "Resolved with workaround", slug: "resolved_workaround",
      incident_lifecycle_stage: IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::CLOSED),
      position: @workspace.incident_statuses.maximum(:position).to_i + 1
    )
  end

  def fields(slug, answers: {})
    IncidentFormPrompt.new(@workspace, incident: @incident, form_slug: slug, answers: answers).fields
  end

  def field(slug, key, answers: {})
    fields(slug, answers: answers).find { |candidate| candidate.key == key }
  end
end
