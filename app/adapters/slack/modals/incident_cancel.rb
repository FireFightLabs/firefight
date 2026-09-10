module Slack
  module Modals
    # Only reached when the Cancel form has fields. With none the command
    # cancels outright.
    module IncidentCancel
      def self.build(incident, private_metadata: nil)
        TerminalForm.build(
          incident,
          form_slug: IncidentForm::SLUG_CANCEL,
          callback_id: Identifiers::CANCEL_INCIDENT_MODAL,
          title: "Cancel incident",
          submit: "Cancel incident",
          close: "Back",
          private_metadata: private_metadata
        )
      end
    end
  end
end
