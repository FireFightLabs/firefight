module Interactions
  class SetRolesHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.private_metadata)
      acting_member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      submitted = submitted_selections(interaction)
      roles = workspace.incident_roles.where(id: submitted.keys).index_by(&:id)

      assignments = {}
      errors = {}

      submitted.each do |role_id, selected_user_id|
        role = roles[role_id]
        next unless role

        if selected_user_id.blank?
          errors[Identifiers.role_block_id(role)] = role.unassign_blocked_reason if clearing_blocked?(incident, role)
          assignments[role] = nil
          next
        end

        member = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: selected_user_id,
          adapter: workspace.adapter
        )
        return provision_error(Identifiers.role_block_id(role)) unless member

        assignments[role] = member
      end

      return { response_action: "errors", errors: errors } if errors.any?

      IncidentLifecycleService.new(workspace).assign_roles(incident, assignments, changed_by: acting_member)

      nil
    end

    def self.submitted_selections(interaction)
      interaction.values.each_with_object({}) do |(block_id, actions), selections|
        next unless block_id.start_with?(Identifiers::ROLE_BLOCK_PREFIX)

        selections[Identifiers.role_id_from_block(block_id)] = actions.dig(Identifiers::ROLE_SELECT, "selected_user")
      end
    end
    private_class_method :submitted_selections

    # Only a role that someone actually holds can be cleared, so leaving an
    # always-empty block empty is not an error.
    def self.clearing_blocked?(incident, role)
      role.unassign_blocked_reason.present? && incident.role_holder(role).present?
    end
    private_class_method :clearing_blocked?

    def self.provision_error(block_id)
      { response_action: "errors", errors: { block_id => "Couldn't load that user's profile from Slack. Please try again in a moment." } }
    end
    private_class_method :provision_error
  end
end
