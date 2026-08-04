module Slack
  module Modals
    # Only reached when a workspace has attached fields to the Cancel form.
    # With none attached the command cancels outright rather than opening an
    # empty dialog.
    module IncidentCancel
      def self.build(incident, private_metadata: nil)
        workspace = incident.workspace
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)

        context = IncidentConditionEvaluator.context_for(incident)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_CANCEL, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident, terminal_stage: IncidentLifecycleStage::CANCELED)
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end

        {
          type: "modal",
          callback_id: Identifiers::CANCEL_INCIDENT_MODAL,
          notify_on_close: true,
          private_metadata: metadata,
          title: { type: "plain_text", text: "Cancel incident" },
          submit: { type: "plain_text", text: "Cancel incident" },
          close: { type: "plain_text", text: "Back" },
          blocks: blocks
        }
      end
    end
  end
end
