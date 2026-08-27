require "test_helper"

class IncidentFieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
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
    tier = fields.find { |field| field["slug"] == @definition.slug }
    assert_equal [ "Enterprise", "Pro", "Free" ], tier["options"].map { |option| option["label"] }
    assert tier["options"].all? { |option| option["enabled"] }
  end

  test "the forms page serializes custom field options too" do
    get settings_forms_url, headers: inertia_headers
    assert_response :success

    fields = response.parsed_body.dig("props", "customFields")
    tier = fields.find { |field| field["slug"] == @definition.slug }
    assert_equal [ "Enterprise", "Pro", "Free" ], tier["options"].map { |option| option["label"] }
  end

  test "create stores options as rows in the order they were given" do
    post incident_field_definitions_url, params: {
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ { label: "Checkout" }, { label: "Search" } ]
    }
    assert_response :redirect

    definition = IncidentFieldDefinition.find_by!(slug: "impact_area", workspace: @workspace)
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
    assert_not IncidentFieldDefinition.exists?(slug: "impact_area", workspace: @workspace)
  end

  test "create drops blank option labels" do
    post incident_field_definitions_url, params: {
      name: "Impact Area",
      field_type: IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ { label: "Checkout" }, { label: "   " } ]
    }
    assert_response :redirect

    definition = IncidentFieldDefinition.find_by!(slug: "impact_area", workspace: @workspace)
    assert_equal [ "Checkout" ], definition.incident_field_options.ordered.pluck(:label)
  end

  test "update renames an option without changing what incidents point at" do
    option = incident_field_options(:customer_tier_pro)
    incident = incidents(:active_critical_ws1)
    incident.update!(custom_fields: { @definition.slug => option.id })

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map do |current|
        { id: current.id, label: current.id == option.id ? "Professional" : current.label }
      end
    )
    assert_response :redirect

    assert_equal "Professional", option.reload.label
    assert_equal option.id, incident.reload.custom_fields[@definition.slug]
    assert_equal "Professional", incident.custom_fields_for_display[@definition.slug]
  end

  test "update refuses to delete an option an incident points at" do
    option = incident_field_options(:customer_tier_pro)
    incidents(:active_critical_ws1).update!(custom_fields: { @definition.slug => option.id })

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

  test "update switches a catalogue-backed field to a fixed list of new options" do
    catalogue_field = incident_field_definitions(:affected_services_ws1)

    patch incident_field_definition_url(catalogue_field), params: {
      name: catalogue_field.name,
      field_type: IncidentFieldDefinition::TYPE_MULTI_SELECT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_FIXED,
      options: [ { label: "EU" }, { label: "US" } ]
    }
    assert_response :redirect

    catalogue_field.reload
    assert_equal IncidentFieldDefinition::OPTION_SOURCE_FIXED, catalogue_field.option_source
    assert_equal [ "EU", "US" ], catalogue_field.incident_field_options.ordered.pluck(:label)
  end

  test "update adds a brand new option to an existing fixed list" do
    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map { |current|
        { id: current.id, label: current.label }
      } + [ { label: "Startup" } ]
    )
    assert_response :redirect

    assert_equal [ "Enterprise", "Pro", "Free", "Startup" ],
      @definition.incident_field_options.ordered.pluck(:label)
  end

  test "update refuses to change the shape of a field incidents already hold values for" do
    option = incident_field_options(:customer_tier_pro)
    incidents(:active_critical_ws1).update!(custom_fields: { @definition.slug => option.id })

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map { |current|
        { id: current.id, label: current.label }
      }
    ).merge(option_source: IncidentFieldDefinition::OPTION_SOURCE_CATALOG)
    assert_response :redirect

    assert_equal IncidentFieldDefinition::OPTION_SOURCE_FIXED, @definition.reload.option_source
  end

  test "update still allows renaming a field incidents already hold values for" do
    option = incident_field_options(:customer_tier_pro)
    incidents(:active_critical_ws1).update!(custom_fields: { @definition.slug => option.id })

    patch incident_field_definition_url(@definition), params: base_update_params(
      options: @definition.incident_field_options.ordered.map { |current|
        { id: current.id, label: current.label }
      }
    ).merge(name: "Customer Segment")
    assert_response :redirect

    assert_equal "Customer Segment", @definition.reload.name
  end

  test "update refuses more enabled options than Slack will render" do
    over_limit = (1..IncidentFieldDefinition::MAX_OPTIONS + 1).map { |n| { label: "Option #{n}" } }

    patch incident_field_definition_url(@definition), params: base_update_params(options: over_limit)
    assert_response :redirect

    assert_equal 3, @definition.reload.incident_field_options.count
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

  # Detaching a field from every form does not unmake the incidents declared
  # with it, and the association refuses to cascade those values away, so the
  # delete used to be offered and then blow up.
  test "a field holding incident values cannot be deleted even with no form using it" do
    definition = @workspace.incident_field_definitions.create!(
      name: "Open ended text", slug: "open_ended_text",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE, position: 60
    )
    IncidentFieldValue.create!(incident: incidents(:active_critical_ws1),
                               incident_field_definition: definition, value_text: "something")

    assert_equal 0, definition.incident_form_fields.count, "no form uses it"

    delete incident_field_definition_path(definition)

    assert IncidentFieldDefinition.exists?(definition.id)
    assert_match(/holds a value on 1 incident/, flash[:alert])
  end

  test "the screen ships the reason so the row can disable Delete" do
    definition = @workspace.incident_field_definitions.create!(
      name: "Open ended text", slug: "open_ended_text",
      field_type: IncidentFieldDefinition::TYPE_TEXT,
      option_source: IncidentFieldDefinition::OPTION_SOURCE_NONE, position: 61
    )
    IncidentFieldValue.create!(incident: incidents(:active_critical_ws1),
                               incident_field_definition: definition, value_text: "something")

    get settings_custom_fields_url, headers: inertia_headers

    row = inertia_props["customFields"].find { |field| field["id"] == definition.id }
    assert_match(/holds a value on 1 incident/, row["deletionBlockedReason"])
  end
end
