module Interactions
  # Edit on a proposed handbook edit opens the form to change it before accepting. trigger_id expires in three seconds,
  # so this stays sync. One already decided says so instead.
  class OpenHandbookProposalEditHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_HANDBOOK

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter
      editable = HandbookProposalService.new(workspace).editable(interaction.action_value)
      if editable.is_a?(String)
        adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: editable)
      else
        adapter.open_handbook_proposal_modal(trigger_id: interaction.trigger_id, proposal: editable)
      end
      nil
    rescue AdapterError::TriggerExpired
      nil
    end
  end
end
