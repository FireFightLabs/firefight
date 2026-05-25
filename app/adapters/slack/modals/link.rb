module Slack
  module Modals
    module Link
      RELATIONSHIP_OPTIONS = {
        IncidentRelationship::RELATED => {
          text: { type: "plain_text", text: "Related" },
          value: IncidentRelationship::RELATED,
          description: { type: "plain_text", text: "Link as contextually related incidents" }
        },
        IncidentRelationship::DUPLICATE => {
          text: { type: "plain_text", text: "Duplicate (merge into target)" },
          value: IncidentRelationship::DUPLICATE,
          description: { type: "plain_text", text: "Mark this incident as a duplicate and cancel it" }
        }
      }.freeze

      def self.build(incident, private_metadata: nil, default_type: IncidentRelationship::RELATED)
        workspace = incident.workspace

        other_incidents = workspace.incidents.where.not(id: incident.id).recent.limit(100)
        incident_options = other_incidents.map do |inc|
          {
            text: { type: "plain_text", text: "#{inc.identifier}: #{(inc.name || 'Untitled').truncate(60)}" },
            value: inc.id
          }
        end
        return nil if incident_options.empty?

        {
          type: "modal",
          callback_id: Identifiers::LINK_INCIDENT_MODAL,
          private_metadata: private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Link incident" },
          submit: { type: "plain_text", text: "Link" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" } },
            {
              type: "input",
              block_id: "relationship_type_block",
              element: {
                type: "static_select",
                action_id: "relationship_type_select",
                options: RELATIONSHIP_OPTIONS.values,
                initial_option: RELATIONSHIP_OPTIONS.fetch(default_type, RELATIONSHIP_OPTIONS[IncidentRelationship::RELATED])
              },
              label: { type: "plain_text", text: "Relationship type" }
            },
            {
              type: "input",
              block_id: "target_incident_block",
              element: {
                type: "static_select",
                action_id: "target_incident_select",
                placeholder: { type: "plain_text", text: "Select an incident" },
                options: incident_options
              },
              label: { type: "plain_text", text: "Target incident" }
            }
          ]
        }
      end
    end
  end
end
