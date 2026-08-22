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

        context = context_for(incident, state)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident, status_dispatch: true)
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

      # What the incident will hold once this is submitted: the status in front
      # of the responder over the one it still has. Mirrors what
      # Slack::FormSubmission builds on submit, so the fields the modal shows
      # are the fields the submission then asks for.
      def self.context_for(incident, state)
        picked = picked_status_id(incident.workspace, state)
        return IncidentConditionEvaluator.context_for(incident) if picked.nil?

        IncidentConditionEvaluator.context_for(incident).merge(status: picked)
      end
      private_class_method :context_for

      def self.picked_status_id(workspace, state)
        slug = (state.presence || {}).dig(
          "field_status_block", Identifiers::INCIDENT_UPDATE_STATUS_SELECT, "selected_option", "value"
        )
        return nil if slug.blank?

        workspace.incident_statuses.active.where(slug: slug).pick(:id)
      end
      private_class_method :picked_status_id
    end
  end
end
