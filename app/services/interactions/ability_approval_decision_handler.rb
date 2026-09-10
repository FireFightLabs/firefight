module Interactions
  # The model enforces the rules (role at click time, no self-approval, still pending).
  class AbilityApprovalDecisionHandler
    def self.decide(interaction, decision)
      workspace = interaction.workspace
      approval = workspace.ability_approvals.find_by(id: interaction.action_value)
      return nil unless approval

      membership = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      begin
        decision == :approve ? approval.approve!(by: membership) : approval.deny!(by: membership)
      rescue Ability::Approval::NotAllowed => e
        workspace.adapter.post_ephemeral(
          channel_id: interaction.channel_id, user_id: interaction.user_id,
          text: "Cannot #{decision} this request: #{e.message}"
        )
        return nil
      end

      ApprovalNotificationService.mark_resolved!(approval)
      nil
    end
  end
end
