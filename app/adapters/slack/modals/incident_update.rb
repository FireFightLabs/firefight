module Slack
  module Modals
    # `state` is the view's values as Slack sends them back on a status
    # dispatch, empty on first open.
    module IncidentUpdate
      def self.build(incident, private_metadata: nil, state: {})
        workspace = incident.workspace
        metadata = private_metadata || ModalState.encode(incident_id: incident.id)

        picked_slug = picked_status_slug(state)
        context = context_for(incident, workspace, picked_slug)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(
              workspace, form_field,
              incident: incident,
              dispatching: [ IncidentSystemField::KEY_STATUS ],
              selected: { IncidentSystemField::KEY_STATUS => picked_slug }
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

      # Mirrors what Slack::FormSubmission builds on submit, so the modal shows
      # the fields the submission will ask for.
      def self.context_for(incident, workspace, picked_slug)
        base = IncidentConditionEvaluator.context_for(incident)
        return base if picked_slug.blank?

        picked_id = workspace.incident_statuses.active.where(slug: picked_slug).pick(:id)
        picked_id ? base.merge(status: picked_id) : base
      end
      private_class_method :context_for

      def self.picked_status_slug(state)
        FieldBlocks.picked(state, IncidentSystemField::KEY_STATUS)
      end
      private_class_method :picked_status_slug
    end
  end
end
