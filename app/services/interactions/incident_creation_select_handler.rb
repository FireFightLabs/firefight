module Interactions
  # Every dispatching select on the declare dialog does the same thing, hand the
  # view state back so the modal re-renders with conditions re-evaluated. One
  # handler rather than one per select, so adding a source is a block change.
  class IncidentCreationSelectHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      interaction.workspace.adapter.update_incident_creation_modal(
        view_id: interaction.view["id"],
        state: interaction.values || {}
      )

      nil
    rescue StandardError => e
      Rails.logger.error({ event: "incident_creation.select_error", error: e.message })
      nil
    end
  end
end
