module Slack
  module Modals
    # Shared field-block builders used by the incident form modals (declare,
    # update, resolve, cancel). Each method returns one Slack Block Kit
    # `input` block. `build_system` and `build_custom` are the dispatchers
    # that pick the right per-type builder.
    #
    # Every field handed here renders. Deciding that a field has nothing to ask
    # belongs to IncidentFormResolver, which is also what `validate_submission`
    # reads. Suppressing a field here alone leaves submission demanding one the
    # responder was never shown.
    module FieldBlocks
      # The selects that re-render their modal when they change. A dispatching
      # select carries a named action id so the handler can tell the dispatch
      # apart from a submission. Every other input is `field_<key>_input`.
      DISPATCH_ACTION_IDS = {
        IncidentSystemField::KEY_SEVERITY => Identifiers::INCIDENT_CREATION_SEVERITY_SELECT,
        IncidentSystemField::KEY_INCIDENT_TYPE => Identifiers::INCIDENT_CREATION_TYPE_SELECT,
        IncidentSystemField::KEY_VISIBILITY => Identifiers::INCIDENT_CREATION_VISIBILITY_SELECT,
        IncidentSystemField::KEY_STATUS => Identifiers::INCIDENT_UPDATE_STATUS_SELECT
      }.freeze

      # One owner for the block and action ids every builder, submission
      # parser and error anchor agrees on.
      def self.block_id(key)
        "field_#{key}_block"
      end

      def self.input_id(key)
        "field_#{key}_input"
      end

      def self.action_id(key, dispatching: [])
        dispatching.include?(key) ? DISPATCH_ACTION_IDS.fetch(key) : input_id(key)
      end

      # The option a responder has picked in a dispatching select, read off
      # the view state Slack sends back with the dispatch.
      def self.picked(state, key)
        (state.presence || {}).dig(block_id(key), DISPATCH_ACTION_IDS.fetch(key), "selected_option", "value")
      end

      # `dispatching` names the system keys whose select re-renders the modal.
      # `selected` holds what the responder has picked so far, by system key,
      # as the option value (severity, type and status by slug, visibility by
      # its value). `terminal_stage` narrows the status select on the resolve
      # and cancel forms.
      def self.build_system(workspace, form_field, incident: nil, dispatching: [], selected: {}, terminal_stage: nil)
        key = form_field.system_field_key
        dispatch = dispatching.include?(key)

        case key
        when IncidentSystemField::KEY_NAME
          name_block(form_field, incident: incident)
        when IncidentSystemField::KEY_SUMMARY
          summary_block(form_field, incident: incident)
        when IncidentSystemField::KEY_SEVERITY
          slug = selected[key] || incident&.incident_severity&.slug
          severity_block(workspace, form_field, selected_severity_slug: slug, dispatch: dispatch)
        when IncidentSystemField::KEY_INCIDENT_TYPE
          incident_type_block(workspace, form_field, incident: incident, dispatch: dispatch, selected_type_slug: selected[key])
        when IncidentSystemField::KEY_STATUS
          status_block(workspace, form_field, incident: incident, stage: terminal_stage, dispatch: dispatch, selected_status_slug: selected[key])
        when IncidentSystemField::KEY_LEAD
          lead_block(form_field, incident: incident)
        when IncidentSystemField::KEY_VISIBILITY
          visibility_block(form_field, incident: incident, dispatch: dispatch, selected: selected[key])
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

      # Both lists are the registry's, rendered into Block Kit here. The words
      # a responder reads are the same ones the dashboard shows.
      VISIBILITY_OPTIONS = IncidentSystemField::VISIBILITY_CHOICES.map do |choice|
        { text: { type: "plain_text", text: choice.label }, value: choice.value }
      end.freeze

      NEXT_UPDATE_OPTIONS = IncidentSystemField::NEXT_UPDATE_CHOICES.map do |choice|
        { label: choice.label, value: choice.value }
      end.freeze

      DEFAULT_NEXT_UPDATE_MINUTES = IncidentSystemField::DEFAULT_NEXT_UPDATE_MINUTES

      def self.visibility_block(form_field, incident: nil, dispatch: false, selected: nil)
        stored = incident&.is_private ? Incident::VISIBILITY_PRIVATE : Incident::VISIBILITY_PUBLIC
        current = selected.presence || stored
        initial = VISIBILITY_OPTIONS.find { |o| o[:value] == current } || VISIBILITY_OPTIONS.first
        action_id = action_id(IncidentSystemField::KEY_VISIBILITY, dispatching: dispatch ? [ IncidentSystemField::KEY_VISIBILITY ] : [])

        block = {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_VISIBILITY),
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
          action_id: input_id(IncidentSystemField::KEY_LEAD),
          placeholder: copy_placeholder(IncidentSystemField::KEY_LEAD)
        }
        element[:initial_user] = incident.lead.platform_user_id if incident&.lead

        {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_LEAD),
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
          block_id: block_id(IncidentSystemField::KEY_MESSAGE),
          element: {
            type: "plain_text_input",
            action_id: input_id(IncidentSystemField::KEY_MESSAGE),
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
          block_id: block_id(IncidentSystemField::KEY_NEXT_UPDATE),
          element: {
            type: "static_select",
            action_id: input_id(IncidentSystemField::KEY_NEXT_UPDATE),
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
          action_id: input_id(IncidentSystemField::KEY_NAME),
          placeholder: copy_placeholder(IncidentSystemField::KEY_NAME),
          max_length: 200
        }
        element[:initial_value] = incident.name if incident&.name.present?

        {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_NAME),
          element: element,
          label: copy_label(IncidentSystemField::KEY_NAME),
          hint: copy_hint(IncidentSystemField::KEY_NAME),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
      end

      def self.summary_block(form_field, incident: nil)
        element = {
          type: "plain_text_input",
          action_id: input_id(IncidentSystemField::KEY_SUMMARY),
          multiline: true,
          placeholder: copy_placeholder(IncidentSystemField::KEY_SUMMARY),
          max_length: 3000
        }
        element[:initial_value] = incident.summary if incident&.summary.present?

        {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_SUMMARY),
          element: element,
          label: copy_label(IncidentSystemField::KEY_SUMMARY),
          hint: copy_hint(IncidentSystemField::KEY_SUMMARY),
          optional: form_field.required_mode == IncidentFormField::REQUIRED_MODE_OPTIONAL
        }.compact
      end

      def self.severity_block(workspace, form_field, selected_severity_slug: nil, dispatch: false)
        severities = workspace.incident_severities.active.ordered
        default_severity = IncidentSeverity.preselected(severities)
        selected_severity = if selected_severity_slug
          severities.find { |severity| severity.slug == selected_severity_slug } || default_severity
        else
          default_severity
        end

        severity_options = severities.map do |severity|
          { text: { type: "plain_text", text: severity.name }, value: severity.slug }
        end

        initial_option = { text: { type: "plain_text", text: selected_severity.name }, value: selected_severity.slug }

        action_id = action_id(IncidentSystemField::KEY_SEVERITY, dispatching: dispatch ? [ IncidentSystemField::KEY_SEVERITY ] : [])

        block = {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_SEVERITY),
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

      def self.incident_type_block(workspace, form_field, incident: nil, dispatch: false, selected_type_slug: nil)
        types = workspace.incident_types.active.ordered

        type_options = types.map do |type|
          option = { text: { type: "plain_text", text: type.name }, value: type.slug }
          option[:description] = { type: "plain_text", text: type.description } if type.description.present?
          option
        end

        initial_type = if selected_type_slug && type_options.any? { |o| o[:value] == selected_type_slug }
          type_options.find { |o| o[:value] == selected_type_slug }
        elsif incident&.incident_type
          type_options.find { |o| o[:value] == incident.incident_type.slug }
        end

        action_id = action_id(IncidentSystemField::KEY_INCIDENT_TYPE, dispatching: dispatch ? [ IncidentSystemField::KEY_INCIDENT_TYPE ] : [])

        element = {
          type: "static_select",
          action_id: action_id,
          placeholder: copy_placeholder(IncidentSystemField::KEY_INCIDENT_TYPE),
          options: type_options
        }
        element[:initial_option] = initial_type if initial_type

        block = {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_INCIDENT_TYPE),
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
        statuses = statuses.in_stage(stage) if stage
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
          action_id: action_id(IncidentSystemField::KEY_STATUS, dispatching: dispatch ? [ IncidentSystemField::KEY_STATUS ] : []),
          placeholder: copy_placeholder(IncidentSystemField::KEY_STATUS),
          options: status_options
        }
        element[:initial_option] = initial_status if initial_status

        block = {
          type: "input",
          block_id: block_id(IncidentSystemField::KEY_STATUS),
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
          action_id: input_id(defn.slug),
          placeholder: { type: "plain_text", text: "Enter #{defn.name.downcase}" },
          max_length: 3000
        }
        element[:initial_value] = initial_value.to_s if initial_value.present?

        wrap_input(defn, element, optional: optional)
      end

      def self.number_custom_block(defn, optional:, initial_value: nil)
        element = {
          type: "plain_text_input",
          action_id: input_id(defn.slug),
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
          action_id: input_id(defn.slug),
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
          { text: { type: "plain_text", text: label.truncate(IncidentFieldOption::MAX_LABEL_LENGTH) }, value: id }
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
          block_id: block_id(defn.slug),
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
