module Slack
  module Modals
    module IncidentUpdate
      def self.build(incident, private_metadata: nil)
        workspace = incident.workspace
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)

        context = IncidentConditionEvaluator.context_for(incident)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident)
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
    end
  end
end
