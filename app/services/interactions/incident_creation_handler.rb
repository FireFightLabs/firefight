module Interactions
  class IncidentCreationHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      values = interaction.values

      resolver = IncidentFormResolver.new(workspace)
      visible_fields = begin
        resolver.resolve(IncidentForm::SLUG_DECLARE)
      rescue ActiveRecord::RecordNotFound
        []
      end

      raw_params = if visible_fields.any?
        extract_form_values(visible_fields, values)
      else
        extract_fallback_values(values)
      end

      visibility = values.dig("visibility_block", "visibility_select", "selected_option", "value")

      result = if visible_fields.any?
        resolver.validate_submission(IncidentForm::SLUG_DECLARE, raw_params)
      else
        { system_attrs: raw_params, custom_fields: {}, errors: [] }
      end

      if result[:errors].any?
        first_field_key = visible_fields.map { |f|
          f.system_field_key || f.incident_field_definition&.key
        }.compact.first || "name"

        return {
          response_action: "errors",
          errors: { "field_#{first_field_key}_block": result[:errors].first }
        }
      end

      severity_slug = result[:system_attrs]["severity"]
      severity = workspace.incident_severities.active.find_by!(slug: severity_slug)
      status = workspace.incident_statuses.default_status

      incident_type = if result[:system_attrs]["incident_type"].present?
        workspace.incident_types.active.find_by(slug: result[:system_attrs]["incident_type"])
      end

      incident = IncidentLifecycleService.new(workspace).create(
        declared_by: member,
        incident_status: status,
        incident_severity: severity,
        incident_type: incident_type,
        name: result[:system_attrs]["name"],
        summary: result[:system_attrs]["summary"],
        custom_fields: result[:custom_fields].presence || {},
        is_private: visibility == Incident::VISIBILITY_PRIVATE,
        source: Incident::SOURCE_SLACK
      )

      Rails.logger.info({
        event: "incident.creation_started",
        incident_id: incident.id,
        identifier: incident.identifier,
        workspace_id: workspace.id,
        severity: severity_slug
      })

      adapter = workspace.adapter
      { response_action: "update", view: adapter.build_incident_created_view(incident) }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })

      {
        response_action: "errors",
        errors: { field_severity_block: "Invalid severity selection. Please try again." }
      }
    rescue => e
      Rails.logger.error({ event: "incident.creation_error", error: e.message })

      {
        response_action: "errors",
        errors: { field_name_block: "Failed to create incident. Please try again." }
      }
    end

    def self.extract_form_values(visible_fields, values)
      raw_params = {}
      visible_fields.each do |form_field|
        key = form_field.system_field_key || form_field.incident_field_definition&.key
        next unless key

        block_id = "field_#{key}_block"
        action_id = if key == IncidentSystemField::KEY_SEVERITY
          Identifiers::INCIDENT_CREATION_SEVERITY_SELECT
        else
          "field_#{key}_input"
        end

        raw_params[key] = extract_block_value(values, block_id, action_id, form_field)
      end
      raw_params
    end
    private_class_method :extract_form_values

    def self.extract_fallback_values(values)
      {
        "name" => values.dig("field_name_block", "field_name_input", "value"),
        "severity" => values.dig("field_severity_block", Identifiers::INCIDENT_CREATION_SEVERITY_SELECT, "selected_option", "value"),
        "summary" => values.dig("field_summary_block", "field_summary_input", "value")
      }
    end
    private_class_method :extract_fallback_values

    def self.extract_block_value(values, block_id, action_id, form_field)
      block_values = values.dig(block_id, action_id)
      return nil unless block_values

      if form_field.system?
        defn = IncidentSystemField.fetch(form_field.system_field_key)
        field_type = defn.field_type
      else
        field_type = form_field.incident_field_definition&.field_type
      end

      case field_type
      when IncidentFieldDefinition::TYPE_SINGLE_SELECT,
           IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
        block_values.dig("selected_option", "value")
      when IncidentFieldDefinition::TYPE_MULTI_SELECT,
           IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
        block_values["selected_options"]&.map { |o| o["value"] }
      else
        block_values["value"]
      end
    end
    private_class_method :extract_block_value
  end
end
