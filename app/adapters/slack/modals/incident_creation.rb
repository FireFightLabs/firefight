module Slack
  module Modals
    module IncidentCreation
      def self.build(workspace:, selected_severity_slug: nil, selected_type_id: nil)
        visible_fields = resolve_visible_fields(workspace, selected_severity_slug: selected_severity_slug, selected_type_id: selected_type_id)

        blocks = visible_fields.filter_map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, selected_severity_slug: selected_severity_slug, severity_dispatch: true, type_dispatch: true, selected_type_id: selected_type_id)
          else
            FieldBlocks.build_custom(workspace, form_field)
          end
        end

        {
          type: "modal",
          callback_id: Identifiers::INCIDENT_CREATION_MODAL,
          title: { type: "plain_text", text: "Declare an incident" },
          submit: { type: "plain_text", text: "Declare" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: blocks
        }
      end

      def self.resolve_visible_fields(workspace, selected_severity_slug:, selected_type_id:)
        context = {}
        context[:incident_type] = selected_type_id if selected_type_id
        if selected_severity_slug
          severity_id = workspace.incident_severities.where(slug: selected_severity_slug).pick(:id)
          context[:severity] = severity_id if severity_id
        end

        IncidentFormResolver.new(workspace).resolve(IncidentForm::SLUG_DECLARE, context: context)
      end
      private_class_method :resolve_visible_fields
    end
  end
end
