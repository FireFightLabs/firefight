module Slack
  module Modals
    module IncidentClose
      def self.build(incident, private_metadata: nil)
        workspace = incident.workspace
        metadata = private_metadata || incident.id

        context = {
          incident_type: incident.incident_type_id,
          severity: incident.incident_severity_id
        }.compact
        visible_fields = IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_RESOLVE, context: context)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident)
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end
        blocks << lead_block(incident)

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

      def self.lead_block(incident)
        element = {
          type: "users_select",
          action_id: "lead_select",
          placeholder: { type: "plain_text", text: "Select a person" }
        }
        element[:initial_user] = incident.lead.platform_user_id if incident.lead

        {
          type: "input",
          block_id: "lead_block",
          element: element,
          label: { type: "plain_text", text: "Incident Lead" },
          optional: true
        }
      end
    end
  end
end
