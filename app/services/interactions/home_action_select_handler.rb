module Interactions
  class HomeActionSelectHandler
    def self.execute(interaction)
      adapter = WorkspaceAdapter.for(interaction.workspace)
      adapter.update_home_modal(view: interaction.view, selected_command: interaction.selected_value)

      nil
    rescue => e
      Rails.logger.error({ event: "incident_home.update_error", error: e.message })
      nil
    end
  end
end
