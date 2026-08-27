module Slack
  module Modals
    # Resolve and Cancel are the same dialog over a different form. The fields
    # come from the resolver either way, and the two differ only in wording and
    # in which lifecycle stage the transition targets, which is what scopes the
    # status options.
    module TerminalForm
      def self.build(incident, form_slug:, callback_id:, title:, submit:, close:, private_metadata: nil)
        workspace = incident.workspace
        stage = IncidentFormResolver::TERMINAL_STAGE_BY_FORM.fetch(form_slug)

        blocks = IncidentFormResolver.new(workspace).fields_for(incident, form_slug).map do |form_field|
          if form_field.system?
            FieldBlocks.build_system(workspace, form_field, incident: incident, terminal_stage: stage)
          else
            FieldBlocks.build_custom(workspace, form_field, incident: incident)
          end
        end

        {
          type: "modal",
          callback_id: callback_id,
          notify_on_close: true,
          private_metadata: private_metadata || ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: title },
          submit: { type: "plain_text", text: submit },
          close: { type: "plain_text", text: close },
          blocks: blocks
        }
      end
    end
  end
end
