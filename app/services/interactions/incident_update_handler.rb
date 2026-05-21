module Interactions
  class IncidentUpdateHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      values = interaction.values
      resolver = IncidentFormResolver.new(workspace)
      context = build_condition_context(workspace, values, incident)
      visible_fields = begin
        resolver.resolve(IncidentForm::SLUG_UPDATE, context: context)
      rescue ActiveRecord::RecordNotFound
        []
      end

      raw_params = if visible_fields.any?
        extract_form_values(visible_fields, values)
      else
        extract_fallback_values(values)
      end

      form_system_keys = visible_fields.any? ? visible_fields.select(&:system?).map(&:system_field_key).to_set : nil

      result = if visible_fields.any?
        resolver.validate_submission(IncidentForm::SLUG_UPDATE, raw_params, context: context)
      else
        { system_attrs: raw_params, custom_fields: {}, errors: [] }
      end

      if result[:errors].any?
        first_block = first_form_block_id(visible_fields)
        return {
          response_action: "errors",
          errors: { first_block => result[:errors].first }
        }
      end

      system_attrs = result[:system_attrs]
      custom_fields = result[:custom_fields]

      has_field = ->(key) { form_system_keys ? form_system_keys.include?(key) : raw_params.key?(key) }

      new_status = if system_attrs["status"].present?
        workspace.incident_statuses.active.find_by!(slug: system_attrs["status"])
      else
        incident.incident_status
      end

      new_severity = if system_attrs["severity"].present?
        workspace.incident_severities.active.find_by!(slug: system_attrs["severity"])
      else
        incident.incident_severity
      end

      new_type = if has_field.call(IncidentSystemField::KEY_INCIDENT_TYPE)
        system_attrs["incident_type"].present? ? workspace.incident_types.active.find_by!(slug: system_attrs["incident_type"]) : nil
      else
        incident.incident_type
      end

      message = values.dig("message_block", "message_input", "value")
      next_update_minutes = values.dig("next_update_block", "next_update_select", "selected_option", "value")

      attrs = { incident_status: new_status, incident_severity: new_severity, incident_type: new_type }
      attrs[:custom_fields] = incident.custom_fields.merge(custom_fields) if custom_fields.present?

      IncidentLifecycleService.new(workspace).update(
        incident,
        attrs,
        changed_by: member,
        message: message
      )

      if next_update_minutes.present?
        incident.update!(next_update_at: Time.current + next_update_minutes.to_i.minutes)
        IncidentUpdateReminderJob.set(wait: next_update_minutes.to_i.minutes).perform_later(incident.id, incident.next_update_at.iso8601)
      else
        incident.update!(next_update_at: nil)
      end

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.incident_update.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "field_status_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.build_condition_context(workspace, values, incident)
      type_slug = values.dig("field_incident_type_block", "field_incident_type_input", "selected_option", "value")
      type_id = if type_slug.present?
        workspace.incident_types.active.where(slug: type_slug).pick(:id) || incident.incident_type_id
      else
        incident.incident_type_id
      end

      severity_slug = values.dig("field_severity_block", "field_severity_input", "selected_option", "value")
      severity_id = if severity_slug.present?
        workspace.incident_severities.where(slug: severity_slug).pick(:id) || incident.incident_severity_id
      else
        incident.incident_severity_id
      end

      { incident_type: type_id, severity: severity_id }.compact
    end
    private_class_method :build_condition_context

    def self.extract_form_values(visible_fields, values)
      raw_params = {}
      visible_fields.each do |form_field|
        key = form_field.system_field_key || form_field.incident_field_definition&.key
        next unless key

        block_id = "field_#{key}_block"
        action_id = "field_#{key}_input"

        raw_params[key] = extract_block_value(values, block_id, action_id, form_field)
      end
      raw_params
    end
    private_class_method :extract_form_values

    def self.extract_fallback_values(values)
      {
        "status" => values.dig("field_status_block", "field_status_input", "selected_option", "value"),
        "severity" => values.dig("field_severity_block", "field_severity_input", "selected_option", "value"),
        "incident_type" => values.dig("field_incident_type_block", "field_incident_type_input", "selected_option", "value")
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

    def self.first_form_block_id(visible_fields)
      first_key = visible_fields.map { |f|
        f.system_field_key || f.incident_field_definition&.key
      }.compact.first || "status"

      "field_#{first_key}_block"
    end
    private_class_method :first_form_block_id

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed["incident_id"], temp_message_ts: parsed["temp_message_ts"], channel_id: parsed["channel_id"] }
    rescue JSON::ParserError
      { incident_id: raw }
    end
    private_class_method :parse_metadata

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      workspace.adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.incident_update.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
