require "test_helper"

class IncidentFieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents,
           :catalog_types, :incident_field_definitions, :incident_field_options

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @user = users(:alice)
    @definition = incident_field_definitions(:customer_tier_ws1)
    sign_in(@user, @workspace)
  end

  test "the settings page serializes each field with its options" do
    get settings_custom_fields_url, headers: inertia_headers
    assert_response :success

    fields = response.parsed_body.dig("props", "customFields")
    tier = fields.find { |field| field["key"] == @definition.key }
    assert_equal [ "Enterprise", "Pro", "Free" ], tier["options"].map { |option| option["label"] }
    assert tier["options"].all? { |option| option["enabled"] }
  end

  test "create stores options as rows in the order they were given" do
    post incident_field_definitions_url, params: {
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ { label: "Checkout" }, { label: "Search" } ]
    }
    assert_response :redirect

    definition = IncidentFieldDefinition.find_by!(key: "impact_area", workspace: @workspace)
    assert_equal [ "Checkout", "Search" ], definition.incident_field_options.ordered.pluck(:label)
  end

  test "create rejects a fixed select with no options" do
    post incident_field_definitions_url, params: {
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: []
    }
    assert_response :redirect
    assert_not IncidentFieldDefinition.exists?(key: "impact_area", workspace: @workspace)
  end

  test "create drops blank option labels" do
    post incident_field_definitions_url, params: {
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ { label: "Checkout" }, { label: "   " } ]
    }
    assert_response :redirect

    definition = IncidentFieldDefinition.find_by!(key: "impact_area", workspace: @workspace)
    assert_equal [ "Checkout" ], definition.incident_field_options.ordered.pluck(:label)
  end

  test "update renames an option without changing what incidents point at" do
    option = incident_field_options(:customer_tier_pro)
    incident = incidents(:active_critical_ws1)
    incident.update!(custom_fields: { @definition.key => option.id })

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map do |current|
        { id: current.id, label: current.id == option.id ? "Professional" : current.label }
      end
    )
    assert_response :redirect

    assert_equal "Professional", option.reload.label
    assert_equal option.id, incident.reload.custom_fields[@definition.key]
    assert_equal "Professional", incident.custom_fields_for_display[@definition.key]
  end

  test "update refuses to delete an option an incident points at" do
    option = incident_field_options(:customer_tier_pro)
    incidents(:active_critical_ws1).update!(custom_fields: { @definition.key => option.id })

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered
        .reject { |current| current.id == option.id }
        .map { |current| { id: current.id, label: current.label } }
    )
    assert_response :redirect

    assert IncidentFieldOption.exists?(option.id)
  end

  test "update deletes an option nothing points at" do
    option = incident_field_options(:customer_tier_free)

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered
        .reject { |current| current.id == option.id }
        .map { |current| { id: current.id, label: current.label } }
    )
    assert_response :redirect

    assert_not IncidentFieldOption.exists?(option.id)
  end

  test "update disables an option without deleting it" do
    option = incident_field_options(:customer_tier_free)

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map do |current|
        { id: current.id, label: current.label, disabled: current.id == option.id }
      end
    )
    assert_response :redirect

    assert_not option.reload.enabled?
    assert IncidentFieldOption.exists?(option.id)
  end

  private

  def base_update_params(options:)
    {
      name: @definition.name,
      field_type: @definition.field_type,
      option_source: @definition.option_source,
      options: options
    }
  end
end
