module Slack
  module Modals
    module IncidentClose
      def self.build(incident, private_metadata: nil)
        TerminalForm.build(
          incident,
          form_slug: IncidentForm::SLUG_RESOLVE,
          callback_id: Identifiers::CLOSE_INCIDENT_MODAL,
          title: "Close incident",
          submit: "Close incident",
          close: "Cancel",
          private_metadata: private_metadata
        )
      end
    end
  end
end
