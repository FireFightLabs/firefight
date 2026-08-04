module Slack
  module Modals
    module IncidentClose
      def self.build(incident, private_metadata: nil)
        workspace = incident.workspace
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)

        context = IncidentConditionEvaluator.context_for(incident)
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_RESOLVE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident, terminal_stage: IncidentLifecycleStage::CLOSED)
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end

        {
          type: "modal",
          callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
          notify_on_close: true,
          private_metadata: metadata,
          title: { type: "plain_text", text: "Close incident" },
          submit: { type: "plain_text", text: "Close incident" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: blocks
        }
      end
    end
  end
end
