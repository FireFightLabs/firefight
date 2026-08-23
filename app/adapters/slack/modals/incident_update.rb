module Slack
  module Modals
    # The update dialog. Its status select dispatches, so the modal re-renders
    # against the status the responder has picked rather than the one the
    # incident still holds. `state` is the view's values as Slack sends them
    # back on that dispatch, and is empty on first open.
    module IncidentUpdate
      def self.build(incident, private_metadata: nil, state: {})
        workspace = incident.workspace
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)

        picked_slug = picked_status_slug(state)
        context = context_for(incident, workspace, picked_slug)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(
              workspace, form_field,
              incident: incident, status_dispatch: true, selected_status_slug: picked_slug
            )
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end
        {
          type: "modal",
          callback_id: Identifiers::INCIDENT_UPDATE_MODAL,
          notify_on_close: true,
          private_metadata: metadata,
          title: { type: "plain_text", text: "Incident update" },
          submit: { type: "plain_text", text: "Send update" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: blocks
        }
      end

      # What the incident will hold once this is submitted, the status in front
      # of the responder over the one it still has. Mirrors what
      # Slack::FormSubmission builds on submit, so the fields the modal shows
      # are the fields the submission then asks for.
      def self.context_for(incident, workspace, picked_slug)
        base = IncidentConditionEvaluator.context_for(incident)
        return base if picked_slug.blank?

        picked_id = workspace.incident_statuses.active.where(slug: picked_slug).pick(:id)
        picked_id ? base.merge(status: picked_id) : base
      end
      private_class_method :context_for

      def self.picked_status_slug(state)
        (state.presence || {}).dig(
          "field_status_block", Identifiers::INCIDENT_UPDATE_STATUS_SELECT, "selected_option", "value"
        )
      end
      private_class_method :picked_status_slug
    end
  end
end
