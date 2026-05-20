module Interactions
  class CloseIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = parse_metadata(interaction.private_metadata)
      incident = workspace.incidents.find(metadata[:incident_id])
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_closed_error if incident.closed?

      values = interaction.values
      resolver = IncidentFormResolver.new(workspace)
      visible_fields = begin
        resolver.resolve(IncidentForm::SLUG_RESOLVE)
      rescue ActiveRecord::RecordNotFound
        []
      end

      raw_params = if visible_fields.any?
        extract_form_values(visible_fields, values)
      else
        extract_fallback_values(values)
      end

      result = if visible_fields.any?
        resolver.validate_submission(IncidentForm::SLUG_RESOLVE, raw_params)
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

      lead_user_id = values.dig("lead_block", "lead_select", "selected_user")

      resolved_status = workspace.incident_statuses.closed.first
      new_severity = if system_attrs["severity"].present?
        workspace.incident_severities.active.find_by!(slug: system_attrs["severity"])
      else
        incident.incident_severity
      end

      attrs = { incident_status: resolved_status, incident_severity: new_severity }
      attrs[:name] = system_attrs["name"] if system_attrs["name"].present?
      attrs[:summary] = system_attrs["summary"] if system_attrs["summary"].present?
      attrs[:custom_fields] = incident.custom_fields.merge(custom_fields) if custom_fields.present?

      if system_attrs.key?("incident_type") && system_attrs["incident_type"].present?
        attrs[:incident_type] = workspace.incident_types.active.find_by!(slug: system_attrs["incident_type"])
      end

      if lead_user_id.present?
        lead_member = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: lead_user_id,
          adapter: workspace.adapter
        )
        return { response_action: "errors", errors: { "lead_block" => "Couldn't load that user's profile from Slack. Please try again in a moment." } } unless lead_member

        attrs[:lead] = lead_member
      end

      IncidentLifecycleService.new(workspace).close(incident, attrs, changed_by: member)

      delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.close_incident.record_not_found", error: e.message })
      delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "field_summary_block" => "Something went wrong. Please close this modal and try again." } }
    end

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
        "name" => values.dig("field_name_block", "field_name_input", "value"),
        "summary" => values.dig("field_summary_block", "field_summary_input", "value"),
        "severity" => values.dig("field_severity_block", "field_severity_input", "selected_option", "value")
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
      }.compact.first || "summary"

      "field_#{first_key}_block"
    end
    private_class_method :first_form_block_id

    def self.parse_metadata(raw)
      parsed = JSON.parse(raw)
      { incident_id: parsed.fetch("incident_id"), temp_message_ts: parsed["temp_message_ts"].to_s, channel_id: parsed["channel_id"].to_s }
    rescue JSON::ParserError, KeyError => e
      raise "Invalid modal metadata: #{e.message}"
    end
    private_class_method :parse_metadata

    def self.already_closed_error
      { response_action: "errors", errors: { "field_summary_block" => "This incident is already closed." } }
    end
    private_class_method :already_closed_error

    def self.delete_temp_message(workspace, metadata)
      return unless metadata[:temp_message_ts] && metadata[:channel_id]

      workspace.adapter.delete_message(channel_id: metadata[:channel_id], ts: metadata[:temp_message_ts])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.close_incident.delete_temp_failed", error: e.message })
    end
    private_class_method :delete_temp_message
  end
end
