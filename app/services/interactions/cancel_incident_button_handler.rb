module Interactions
  # The Cancel button beside Accept in triage. Mirrors AcceptIncidentHandler:
  # one click, no modal, because a false positive should cost nothing to
  # dismiss. A workspace wanting to capture a reason attaches a field to the
  # Cancel form, which routes through CancelIncidentHandler instead.
  class CancelIncidentButtonHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident = workspace.incidents.find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      if incident.incident_status.incident_lifecycle_stage.canceled?
        Rails.logger.warn({ event: "incident.cancel_skipped", incident_id: incident.id, reason: "already_canceled" })
        return nil
      end

      status = workspace.incident_statuses.canceled.active.ordered.first
      if status.nil?
        Rails.logger.warn({ event: "incident.cancel_skipped", incident_id: incident.id, reason: "no_canceled_status" })
        return nil
      end

      IncidentLifecycleService.new(workspace).cancel(
        incident, { incident_status: status }, changed_by: member
      )

      Rails.logger.info({
        event: "incident.canceled",
        incident_id: incident.id,
        identifier: incident.identifier,
        canceled_by: member.platform_user_id
      })

      nil
    end
  end
end
