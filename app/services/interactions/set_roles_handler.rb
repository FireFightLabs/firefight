module Interactions
  class SetRolesHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.metadata.incident_id)
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
        return provision_error(workspace, Identifiers.role_block_id(role)) unless member

        assignments[role] = member
      end

      return workspace.adapter.modal_errors_response(errors) if errors.any?

      IncidentLifecycleService.new(workspace).assign_roles(incident, assignments, changed_by: acting_member)

      nil
    end

    def self.submitted_selections(interaction)
      adapter = interaction.workspace.adapter
      interaction.values.each_key.with_object({}) do |block_id, selections|
        next unless block_id.start_with?(Identifiers::ROLE_BLOCK_PREFIX)

        selections[Identifiers.role_id_from_block(block_id)] =
          adapter.submitted_value(values: interaction.values, block_id: block_id, input_id: Identifiers::ROLE_SELECT, kind: PlatformAdapter::Input::USER)
      end
    end
    private_class_method :submitted_selections

    # Leaving an always-empty block empty is not a clear.
    def self.clearing_blocked?(incident, role)
      role.unassign_blocked_reason.present? && incident.role_holder(role).present?
    end
    private_class_method :clearing_blocked?

    def self.provision_error(workspace, block_id)
      workspace.adapter.modal_errors_response({ block_id => "Couldn't load that user's profile from Slack. Please try again in a moment." })
    end
    private_class_method :provision_error
  end
end
