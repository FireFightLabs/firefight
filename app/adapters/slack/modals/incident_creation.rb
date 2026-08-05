module Slack
  module Modals
    # The declare dialog. Re-rendered by Slack every time one of its dispatching
    # selects changes, so conditions can read what the responder has picked so
    # far. `state` is the view's values as Slack sends them back, which is why
    # adding another source is a block change rather than a signature change.
    module IncidentCreation
      DISPATCHING_SELECTS = {
        IncidentSystemField::KEY_SEVERITY => Identifiers::INCIDENT_CREATION_SEVERITY_SELECT,
        IncidentSystemField::KEY_INCIDENT_TYPE => Identifiers::INCIDENT_CREATION_TYPE_SELECT,
        IncidentSystemField::KEY_VISIBILITY => Identifiers::INCIDENT_CREATION_VISIBILITY_SELECT
      }.freeze

      def self.build(workspace:, state: {})
        selected = selections(workspace, state)

        blocks = resolve_visible_fields(workspace, selected).filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(
              workspace, form_field,
              selected_severity_slug: selected[:severity_slug],
              severity_dispatch: true, type_dispatch: true, visibility_dispatch: true,
              selected_type_id: selected[:incident_type_id],
              selected_visibility: selected[:visibility]
            )
          else
            FieldBlocks.build_custom(workspace, form_field)
          end
        end

        {
          type: "modal",
          callback_id: Identifiers::INCIDENT_CREATION_MODAL,
          title: { type: "plain_text", text: "Declare an incident" },
          submit: { type: "plain_text", text: "Declare" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: blocks
        }
      end

      # What the responder has chosen so far, read off the view state Slack
      # returns with every dispatch.
      def self.selections(workspace, state)
        state = state.presence || {}
        severity_slug = picked(state, IncidentSystemField::KEY_SEVERITY)
        type_slug = picked(state, IncidentSystemField::KEY_INCIDENT_TYPE)

        {
          severity_slug: severity_slug,
          severity_id: severity_slug && workspace.incident_severities.where(slug: severity_slug).pick(:id),
          incident_type_id: type_slug && workspace.incident_types.active.where(slug: type_slug).pick(:id),
          visibility: picked(state, IncidentSystemField::KEY_VISIBILITY)
        }
      end

      def self.picked(state, system_key)
        state.dig("field_#{system_key}_block", DISPATCHING_SELECTS.fetch(system_key), "selected_option", "value")
      end
      private_class_method :picked

      def self.resolve_visible_fields(workspace, selected)
        context = IncidentConditionEvaluator.context(
          incident_type: selected[:incident_type_id],
          severity: selected[:severity_id],
          visibility: selected[:visibility]
        )

        IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_DECLARE, context: context)
      end
      private_class_method :resolve_visible_fields
    end
  end
end
