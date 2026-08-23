require "test_helper"

class IncidentDetailSerializerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incident_types, :incident_roles,
           :incident_role_assignments, :incidents

  test "nested people and type ride through their own serializers" do
    incident = incidents(:active_critical_ws1)
    json = IncidentDetailSerializer.one(incident).as_json

    assert_equal incident.declared_by.user.name, json["declaredBy"]["name"]
    assert_equal incident.incident_type.name, json["type"]["name"] if incident.incident_type
    assert json["roles"].is_a?(Array)
    assert json["roles"].none? { |role| role["slug"] == IncidentRole::SLUG_INCIDENT_LEAD }
  end

  test "a missing lead or type is written as null, the shape the page already handles" do
    incident = incidents(:active_critical_ws1)
    incident.incident_role_assignments.destroy_all
    incident.update_column(:incident_type_id, nil)

    json = IncidentDetailSerializer.one(incident).as_json

    assert json.key?("lead")
    assert_nil json["lead"]
    assert_nil json["type"]
  end
end
