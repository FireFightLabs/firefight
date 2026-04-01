module Interactions
  class AcceptIncidentHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      unless incident.incident_status.triage?
        Rails.logger.warn({
          event: "incident.accept_skipped",
          incident_id: incident.id,
          reason: "not_in_triage"
        })
        return nil
      end

      active_stage = IncidentLifecycleStage.find_by!(key: IncidentLifecycleStage::ACTIVE)
      active_status = workspace.incident_statuses.active
        .where(incident_lifecycle_stage: active_stage)
        .ordered
        .first!

      IncidentLifecycleService.new(workspace).accept(
        incident,
        { incident_status: active_status },
        changed_by: member
      )

      Rails.logger.info({
        event: "incident.accepted",
        incident_id: incident.id,
        identifier: incident.identifier,
        accepted_by: member.platform_user_id
      })

      nil
    end
  end
end
