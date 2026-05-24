module Slack
  module Modals
    module IncidentUpdate
      def self.build(incident, private_metadata: nil)
        workspace = incident.workspace
        metadata = private_metadata || incident.id

        context = {
          incident_type: incident.incident_type_id,
          severity: incident.incident_severity_id
        }.compact
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_UPDATE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident)
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end
        # `message` is transient (not an incident attribute) — kept hardcoded.
        blocks << message_block

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

      def self.message_block
        {
          type: "input",
          block_id: "message_block",
          element: {
            type: "plain_text_input",
            action_id: "message_input",
            multiline: true,
            placeholder: { type: "plain_text", text: "What's happening at the moment? What are you doing next?" },
            max_length: 3000
          },
          label: { type: "plain_text", text: "Message" },
          optional: true
        }
      end
    end
  end
end
