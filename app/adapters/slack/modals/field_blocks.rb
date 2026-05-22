module Slack
  module Modals
    # Shared field-block builders used by the three incident form modals
    # (declare, update, close). Each method returns one Slack Block Kit
    # `input` block. `build_system` and `build_custom` are the dispatchers
    # that pick the right per-type builder.
    module FieldBlocks
      def self.build_system(workspace, form_field, selected_severity_slug: nil, incident: nil, severity_dispatch: false, type_dispatch: false, selected_type_id: nil)
        case form_field.system_field_key
        when IncidentSystemField::KEY_NAME
          name_block(form_field, incident: incident)
        when IncidentSystemField::KEY_SUMMARY
          summary_block(form_field, incident: incident)
        when IncidentSystemField::KEY_SEVERITY
          slug = selected_severity_slug || incident&.incident_severity&.slug
          severity_block(workspace, form_field, selected_severity_slug: slug, dispatch: severity_dispatch)
        when IncidentSystemField::KEY_INCIDENT_TYPE
          incident_type_block(workspace, form_field, incident: incident, dispatch: type_dispatch, selected_type_id: selected_type_id)
        when IncidentSystemField::KEY_STATUS
          status_block(workspace, form_field, incident: incident)
        end
      end

      def self.build_custom(workspace, form_field, incident: nil)
        defn = form_field.incident_field_definition
        return nil unless defn

        optional = form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        current_value = incident&.custom_fields&.dig(defn.key)

        case defn.field_type
        when IncidentFieldDefinition::TYPE_TEXT, IncidentFieldDefinition::TYPE_LINK
          text_custom_block(defn, optional: optional, initial_value: current_value)
        when IncidentFieldDefinition::TYPE_NUMBER
          number_custom_block(defn, optional: optional, initial_value: current_value)
        when IncidentFieldDefinition::TYPE_SINGLE_SELECT
          single_select_custom_block(workspace, defn, optional: optional, initial_value: current_value)
        when IncidentFieldDefinition::TYPE_MULTI_SELECT
          multi_select_custom_block(workspace, defn, optional: optional, initial_values: current_value)
        when IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
          catalog_reference_block(workspace, defn, optional: optional, initial_value: current_value)
        when IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
          catalog_multi_reference_block(workspace, defn, optional: optional, initial_values: current_value)
        end
      end

      def self.visibility_block
        {
          type: "input",
          block_id: "visibility_block",
          element: {
            type: "static_select",
            action_id: "visibility_select",
            options: [
              { text: { type: "plain_text", text: "Everyone (public)" }, value: Incident::VISIBILITY_PUBLIC },
              { text: { type: "plain_text", text: "Private" }, value: Incident::VISIBILITY_PRIVATE }
            ],
            initial_option: { text: { type: "plain_text", text: "Everyone (public)" }, value: Incident::VISIBILITY_PUBLIC }
          },
          label: { type: "plain_text", text: "Who should be able to see this incident?" },
          hint: { type: "plain_text", text: "Public incidents are visible to everyone in the workspace. Private incidents are only accessible to invited members." }
        }
      end

      def self.name_block(form_field, incident: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_name_input",
          placeholder: { type: "plain_text", text: "Write something" },
          max_length: 200
        }
        element[:initial_value] = incident.name if incident&.name.present?

        {
          type: "input",
          block_id: "field_name_block",
          element: element,
          label: { type: "plain_text", text: "Incident name" },
          hint: { type: "plain_text", text: "Give a short description of what is happening. If you'd like to, you can leave it blank and change it later" },
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }
      end

      def self.summary_block(form_field, incident: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_summary_input",
          multiline: true,
          placeholder: { type: "plain_text", text: "Think about what you'd like to read if you were coming to the incident fresh..." },
          max_length: 3000
        }
        element[:initial_value] = incident.summary if incident&.summary.present?

        {
          type: "input",
          block_id: "field_summary_block",
          element: element,
          label: { type: "plain_text", text: "Summary" },
          hint: { type: "plain_text", text: "Your current understanding of what happened in the incident, and the impact it had. It's fine to go into detail here." },
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }
      end

      def self.severity_block(workspace, form_field, selected_severity_slug: nil, dispatch: false)
        severities = workspace.incident_severities.active.ordered
        default_severity = severities.find(&:is_default?) || severities.last
        selected_severity = if selected_severity_slug
          severities.find { |s| s.slug == selected_severity_slug } || default_severity
        else
          default_severity
        end

        severity_options = severities.map do |severity|
          { text: { type: "plain_text", text: severity.name }, value: severity.slug }
        end

        initial_option = { text: { type: "plain_text", text: selected_severity.name }, value: selected_severity.slug }

        action_id = dispatch ? Identifiers::INCIDENT_CREATION_SEVERITY_SELECT : "field_severity_input"

        block = {
          type: "input",
          block_id: "field_severity_block",
          element: {
            type: "static_select",
            action_id: action_id,
            placeholder: { type: "plain_text", text: "Select severity" },
            options: severity_options,
            initial_option: initial_option
          },
          label: { type: "plain_text", text: "Severity" }
        }
        block[:dispatch_action] = true if dispatch
        block[:hint] = { type: "plain_text", text: selected_severity.description } if selected_severity.description.present?
        block
      end

      def self.incident_type_block(workspace, form_field, incident: nil, dispatch: false, selected_type_id: nil)
        types = workspace.incident_types.active.ordered
        return nil unless types.any?

        type_options = types.map do |type|
          option = { text: { type: "plain_text", text: type.name }, value: type.slug }
          option[:description] = { type: "plain_text", text: type.description } if type.description.present?
          option
        end

        selected_type = selected_type_id ? types.find { |t| t.id == selected_type_id } : nil

        initial_type = if selected_type
          type_options.find { |o| o[:value] == selected_type.slug }
        elsif incident&.incident_type
          type_options.find { |o| o[:value] == incident.incident_type.slug }
        end

        action_id = dispatch ? Identifiers::INCIDENT_CREATION_TYPE_SELECT : "field_incident_type_input"

        element = {
          type: "static_select",
          action_id: action_id,
          placeholder: { type: "plain_text", text: "Select a type" },
          options: type_options
        }
        element[:initial_option] = initial_type if initial_type

        block = {
          type: "input",
          block_id: "field_incident_type_block",
          element: element,
          label: { type: "plain_text", text: "Incident Type" },
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }
        block[:dispatch_action] = true if dispatch
        block
      end

      def self.status_block(workspace, form_field, incident: nil)
        statuses = workspace.incident_statuses.active.ordered
        status_options = statuses.map do |status|
          option = { text: { type: "plain_text", text: status.name }, value: status.slug }
          option[:description] = { type: "plain_text", text: status.description } if status.description.present?
          option
        end

        initial_status = incident && status_options.find { |o| o[:value] == incident.incident_status.slug }

        element = {
          type: "static_select",
          action_id: "field_status_input",
          placeholder: { type: "plain_text", text: "Select status" },
          options: status_options
        }
        element[:initial_option] = initial_status if initial_status

        {
          type: "input",
          block_id: "field_status_block",
          element: element,
          label: { type: "plain_text", text: "Status" }
        }
      end

      def self.text_custom_block(defn, optional:, initial_value: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Enter #{defn.name.downcase}" },
          max_length: 3000
        }
        element[:initial_value] = initial_value.to_s if initial_value.present?

        wrap_input(defn, element, optional: optional)
      end

      def self.number_custom_block(defn, optional:, initial_value: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Enter a number" }
        }
        element[:initial_value] = initial_value.to_s if initial_value.present?

        wrap_input(defn, element, optional: optional)
      end

      def self.single_select_custom_block(workspace, defn, optional:, initial_value: nil)
        options = custom_field_options(workspace, defn)
        return nil if options.empty?

        element = {
          type: "static_select",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Select #{defn.name.downcase}" },
          options: options
        }
        initial_opt = initial_value && options.find { |o| o[:value] == initial_value }
        element[:initial_option] = initial_opt if initial_opt

        wrap_input(defn, element, optional: optional)
      end

      def self.multi_select_custom_block(workspace, defn, optional:, initial_values: nil)
        options = custom_field_options(workspace, defn)
        return nil if options.empty?

        element = {
          type: "multi_static_select",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Select #{defn.name.downcase}" },
          options: options
        }
        if initial_values.is_a?(Array) && initial_values.any?
          initial_opts = options.select { |o| initial_values.include?(o[:value]) }
          element[:initial_options] = initial_opts if initial_opts.any?
        end

        wrap_input(defn, element, optional: optional)
      end

      def self.catalog_reference_block(workspace, defn, optional:, initial_value: nil)
        options = catalog_options(workspace, defn)
        return nil if options.empty?

        element = {
          type: "static_select",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Select #{defn.name.downcase}" },
          options: options
        }
        initial_opt = initial_value && options.find { |o| o[:value] == initial_value }
        element[:initial_option] = initial_opt if initial_opt

        wrap_input(defn, element, optional: optional)
      end

      def self.catalog_multi_reference_block(workspace, defn, optional:, initial_values: nil)
        options = catalog_options(workspace, defn)
        return nil if options.empty?

        element = {
          type: "multi_static_select",
          action_id: "field_#{defn.key}_input",
          placeholder: { type: "plain_text", text: "Select #{defn.name.downcase}" },
          options: options
        }
        if initial_values.is_a?(Array) && initial_values.any?
          initial_opts = options.select { |o| initial_values.include?(o[:value]) }
          element[:initial_options] = initial_opts if initial_opts.any?
        end

        wrap_input(defn, element, optional: optional)
      end

      def self.custom_field_options(workspace, defn)
        if defn.fixed_options?
          defn.options.map { |opt| { text: { type: "plain_text", text: opt }, value: opt } }
        elsif defn.catalog_options?
          catalog_options(workspace, defn)
        else
          []
        end
      end

      def self.catalog_options(workspace, defn)
        catalog_entries_for(workspace, defn).map do |entry|
          { text: { type: "plain_text", text: entry.name.truncate(75) }, value: entry.id }
        end
      end

      def self.catalog_entries_for(workspace, defn)
        return [] if defn.catalog_type_id.blank?

        workspace.catalog_entries.active.where(catalog_type_id: defn.catalog_type_id).order(:name)
      end

      def self.wrap_input(defn, element, optional:)
        block = {
          type: "input",
          block_id: "field_#{defn.key}_block",
          element: element,
          label: { type: "plain_text", text: defn.name },
          optional: optional
        }
        block[:hint] = { type: "plain_text", text: defn.description } if defn.description.present?
        block
      end
    end
  end
end
