module Slack
  module Modals
    module IncidentUpdate
      NEXT_UPDATE_OPTIONS = [
        { label: "5 minutes", value: "5" },
        { label: "15 minutes", value: "15" },
        { label: "30 minutes", value: "30" },
        { label: "1 hour", value: "60" },
        { label: "3 hours", value: "180" },
        { label: "1 day", value: "1440" },
        { label: "7 days", value: "10080" }
      ].freeze

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
        blocks << message_block
        blocks << next_update_block

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

      def self.next_update_block
        {
          type: "input",
          block_id: "next_update_block",
          element: {
            type: "static_select",
            action_id: "next_update_select",
            placeholder: { type: "plain_text", text: "Select a time" },
            options: next_update_options
          },
          label: { type: "plain_text", text: "When will you provide the next update?" },
          optional: true
        }
      end

      def self.next_update_options
        NEXT_UPDATE_OPTIONS.map do |opt|
          { text: { type: "plain_text", text: opt[:label] }, value: opt[:value] }
        end
      end
    end
  end
end
