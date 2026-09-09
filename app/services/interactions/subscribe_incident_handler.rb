module Interactions
  # The Subscribe button on the announcement. One shared message cannot show
  # each reader their own state, so the button toggles and the answer comes
  # back as an ephemeral only the clicker sees.
  class SubscribeIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace, platform_user_id: interaction.user_id, adapter: workspace.adapter
      )
      return nil unless member

      subscribed = incident.toggle_subscription!(member)
      workspace.adapter.post_ephemeral(
        channel_id: interaction.channel_id,
        user_id: interaction.user_id,
        text: notice(incident, subscribed)
      )
      nil
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.subscribe_incident.notice_failed", error: e.message }.to_json)
      nil
    end

    def self.notice(incident, subscribed)
      if subscribed
        "You are subscribed to #{incident.identifier}. Every update Firefight posts about it will reach you as a direct message. Click Subscribe again to stop."
      else
        "You are no longer subscribed to #{incident.identifier}."
      end
    end
  end
end
