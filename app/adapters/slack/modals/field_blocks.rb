module Slack
  module Modals
    # Shared field-block builders used by the incident form modals (declare,
    # update, resolve, cancel). Each method returns one Slack Block Kit
    # `input` block. `build_system` and `build_custom` are the dispatchers
    # that pick the right per-type builder.
    #
    # Every field handed here renders. Deciding that a field has nothing to ask
    # belongs to IncidentFormResolver, which is also what `validate_submission`
    # reads: suppressing a field here alone leaves submission demanding one the
    # responder was never shown.
    module FieldBlocks
      def self.build_system(workspace, form_field, selected_severity_slug: nil, incident: nil, severity_dispatch: false, type_dispatch: false, visibility_dispatch: false, status_dispatch: false, selected_type_id: nil, selected_visibility: nil, selected_status_slug: nil, terminal_stage: nil)
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
          status_block(workspace, form_field, incident: incident, stage: terminal_stage, dispatch: status_dispatch, selected_status_slug: selected_status_slug)
        when IncidentSystemField::KEY_LEAD
          lead_block(form_field, incident: incident)
        when IncidentSystemField::KEY_VISIBILITY
          visibility_block(form_field, incident: incident, dispatch: visibility_dispatch, selected: selected_visibility)
        when IncidentSystemField::KEY_NEXT_UPDATE
          next_update_block(form_field)
        when IncidentSystemField::KEY_MESSAGE
          message_block(form_field)
        end
      end

      def self.build_custom(_workspace, form_field, incident: nil)
        defn = form_field.incident_field_definition
        optional = form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        current_value = incident&.custom_fields&.dig(defn.slug)

        if defn.selectable?
          select_custom_block(defn, optional: optional, current_value: current_value)
        elsif defn.field_type == IncidentFieldDefinition::TYPE_NUMBER
          number_custom_block(defn, optional: optional, initial_value: current_value)
        else
          text_custom_block(defn, optional: optional, initial_value: current_value)
        end
      end

      VISIBILITY_OPTIONS = [
        { text: { type: "plain_text", text: "Everyone (public)" }, value: Incident::VISIBILITY_PUBLIC },
        { text: { type: "plain_text", text: "Private" },           value: Incident::VISIBILITY_PRIVATE }
      ].freeze

      NEXT_UPDATE_OPTIONS = [
        { label: "5 minutes", value: "5" },
        { label: "15 minutes", value: "15" },
        { label: "30 minutes", value: "30" },
        { label: "1 hour", value: "60" },
        { label: "3 hours", value: "180" },
        { label: "1 day", value: "1440" },
        { label: "7 days", value: "10080" }
      ].freeze

      DEFAULT_NEXT_UPDATE_MINUTES = "15".freeze

      def self.visibility_block(form_field, incident: nil, dispatch: false, selected: nil)
        stored = incident&.is_private ? Incident::VISIBILITY_PRIVATE : Incident::VISIBILITY_PUBLIC
        current = selected.presence || stored
        initial = VISIBILITY_OPTIONS.find { |o| o[:value] == current } || VISIBILITY_OPTIONS.first
        action_id = dispatch ? Identifiers::INCIDENT_CREATION_VISIBILITY_SELECT : "field_visibility_input"

        block = {
          type: "input",
          block_id: "field_visibility_block",
          element: {
            type: "static_select",
            action_id: action_id,
            options: VISIBILITY_OPTIONS,
            initial_option: initial
          },
          label: copy_label(IncidentSystemField::KEY_VISIBILITY),
          hint: copy_hint(IncidentSystemField::KEY_VISIBILITY),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
        block[:dispatch_action] = true if dispatch
        block
      end

      def self.lead_block(form_field, incident: nil)
        element = {
          type: "users_select",
          action_id: "field_lead_input",
          placeholder: copy_placeholder(IncidentSystemField::KEY_LEAD)
        }
        element[:initial_user] = incident.lead.platform_user_id if incident&.lead

        {
          type: "input",
          block_id: "field_lead_block",
          element: element,
          label: copy_label(IncidentSystemField::KEY_LEAD),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }
      end

      # The update itself, written by a responder. Unlike every other field
      # here it lands on the IncidentUpdate rather than the Incident, because an
      # incident collects many messages over its life.
      def self.message_block(form_field)
        {
          type: "input",
          block_id: "field_message_block",
          element: {
            type: "plain_text_input",
            action_id: "field_message_input",
            multiline: true,
            placeholder: copy_placeholder(IncidentSystemField::KEY_MESSAGE),
            max_length: 3000
          },
          label: copy_label(IncidentSystemField::KEY_MESSAGE),
          hint: copy_hint(IncidentSystemField::KEY_MESSAGE),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
      end

      def self.next_update_block(form_field)
        options = NEXT_UPDATE_OPTIONS.map { |o| { text: { type: "plain_text", text: o[:label] }, value: o[:value] } }

        {
          type: "input",
          block_id: "field_next_update_block",
          element: {
            type: "static_select",
            action_id: "field_next_update_input",
            placeholder: copy_placeholder(IncidentSystemField::KEY_NEXT_UPDATE),
            options: options,
            initial_option: options.find { |o| o[:value] == DEFAULT_NEXT_UPDATE_MINUTES }
          },
          label: copy_label(IncidentSystemField::KEY_NEXT_UPDATE),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }
      end

      def self.name_block(form_field, incident: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_name_input",
          placeholder: copy_placeholder(IncidentSystemField::KEY_NAME),
          max_length: 200
        }
        element[:initial_value] = incident.name if incident&.name.present?

        {
          type: "input",
          block_id: "field_name_block",
          element: element,
          label: copy_label(IncidentSystemField::KEY_NAME),
          hint: copy_hint(IncidentSystemField::KEY_NAME),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
      end

      def self.summary_block(form_field, incident: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_summary_input",
          multiline: true,
          placeholder: copy_placeholder(IncidentSystemField::KEY_SUMMARY),
          max_length: 3000
        }
        element[:initial_value] = incident.summary if incident&.summary.present?

        {
          type: "input",
          block_id: "field_summary_block",
          element: element,
          label: copy_label(IncidentSystemField::KEY_SUMMARY),
          hint: copy_hint(IncidentSystemField::KEY_SUMMARY),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
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
            placeholder: copy_placeholder(IncidentSystemField::KEY_SEVERITY),
            options: severity_options,
            initial_option: initial_option
          },
          label: copy_label(IncidentSystemField::KEY_SEVERITY),
          hint: copy_hint(IncidentSystemField::KEY_SEVERITY)
        }.compact
        block[:dispatch_action] = true if dispatch
        # The chosen severity explains itself better than a static hint can, so
        # it takes over once there is one to show.
        block[:hint] = { type: "plain_text", text: selected_severity.description } if selected_severity.description.present?
        block
      end

      def self.incident_type_block(workspace, form_field, incident: nil, dispatch: false, selected_type_id: nil)
        types = workspace.incident_types.active.ordered

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
          placeholder: copy_placeholder(IncidentSystemField::KEY_INCIDENT_TYPE),
          options: type_options
        }
        element[:initial_option] = initial_type if initial_type

        block = {
          type: "input",
          block_id: "field_incident_type_block",
          element: element,
          label: copy_label(IncidentSystemField::KEY_INCIDENT_TYPE),
          hint: copy_hint(IncidentSystemField::KEY_INCIDENT_TYPE),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
        block[:dispatch_action] = true if dispatch
        block
      end

      # On a terminal form the only sensible answers are the statuses in the
      # stage that transition moves to. Offering the full list would let a
      # responder resolve an incident into Investigating.
      def self.status_block(workspace, form_field, incident: nil, stage: nil, dispatch: false, selected_status_slug: nil)
        statuses = workspace.incident_statuses.active.ordered
        if stage
          statuses = statuses.joins(:incident_lifecycle_stage)
            .where(incident_lifecycle_stages: { key: stage })
        end
        status_options = statuses.map do |status|
          option = { text: { type: "plain_text", text: status.name }, value: status.slug }
          option[:description] = { type: "plain_text", text: status.description } if status.description.present?
          option
        end

        # The pick wins over what the incident still holds, so the re-render a
        # dispatch triggers does not snap the select back to the old status.
        current_slug = selected_status_slug.presence || incident&.incident_status&.slug
        initial_status = current_slug && status_options.find { |o| o[:value] == current_slug }

        element = {
          type: "static_select",
          action_id: dispatch ? Identifiers::INCIDENT_UPDATE_STATUS_SELECT : "field_status_input",
          placeholder: copy_placeholder(IncidentSystemField::KEY_STATUS),
          options: status_options
        }
        element[:initial_option] = initial_status if initial_status

        block = {
          type: "input",
          block_id: "field_status_block",
          element: element,
          label: copy_label(IncidentSystemField::KEY_STATUS),
          hint: copy_hint(IncidentSystemField::KEY_STATUS)
        }.compact
        block[:dispatch_action] = true if dispatch
        block
      end

      def self.text_custom_block(defn, optional:, initial_value: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_#{defn.slug}_input",
          placeholder: { type: "plain_text", text: "Enter #{defn.name.downcase}" },
          max_length: 3000
        }
        element[:initial_value] = initial_value.to_s if initial_value.present?

        wrap_input(defn, element, optional: optional)
      end

      def self.number_custom_block(defn, optional:, initial_value: nil)
        element = {
          type: "plain_text_input",
          action_id: "field_#{defn.slug}_input",
          placeholder: { type: "plain_text", text: "Enter a number" }
        }
        element[:initial_value] = initial_value.to_s if initial_value.present?

        wrap_input(defn, element, optional: optional)
      end

      # One builder for every field that picks from a set. A fixed list and a
      # catalog type differ only in where selectable_values reads from, and
      # single versus multi only in which Block Kit keys carry the selection.
      def self.select_custom_block(defn, optional:, current_value:)
        options = custom_field_options(defn)

        element = {
          type: defn.multi_valued? ? "multi_static_select" : "static_select",
          action_id: "field_#{defn.slug}_input",
          placeholder: { type: "plain_text", text: "Select #{defn.name.downcase}" },
          options: options
        }

        if defn.multi_valued?
          selected = options.select { |option| Array(current_value).include?(option[:value]) }
          element[:initial_options] = selected if selected.any?
        else
          selected = options.find { |option| option[:value] == current_value }
          element[:initial_option] = selected if selected
        end

        wrap_input(defn, element, optional: optional)
      end

      def self.custom_field_options(defn)
        defn.selectable_values.map do |id, label|
          { text: { type: "plain_text", text: label.truncate(75) }, value: id }
        end
      end

      # Responder-facing copy lives in IncidentSystemField so the Slack modal
      # and the form editor's preview render the same words.
      def self.copy_label(key)
        { type: "plain_text", text: IncidentSystemField.fetch(key).label }
      end

      # nil when the field carries no hint, so the caller's compact drops the
      # key rather than sending Slack an empty plain_text element.
      def self.copy_hint(key)
        hint = IncidentSystemField.fetch(key).hint
        return nil if hint.blank?

        { type: "plain_text", text: hint }
      end

      def self.copy_placeholder(key)
        placeholder = IncidentSystemField.fetch(key).placeholder
        return nil if placeholder.blank?

        { type: "plain_text", text: placeholder }
      end

      def self.wrap_input(defn, element, optional:)
        block = {
          type: "input",
          block_id: "field_#{defn.slug}_block",
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
