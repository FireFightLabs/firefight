module Interactions
  class CloseIncidentHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = Slack::PrivateMetadata.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_closed_error if incident.closed?

      submission = Slack::FormSubmission.new(
        workspace: workspace,
        form_slug: IncidentForm::SLUG_RESOLVE,
        values: interaction.values,
        incident: incident
      ).parse

      if submission.errors.any?
        return {
          response_action: "errors",
          errors: { submission.first_error_block_id => submission.errors.first }
        }
      end

      lead_member, lead_error = resolve_lead(workspace, submission)
      return lead_error if lead_error

      attrs = build_close_attrs(workspace, incident, submission, lead_member)

      IncidentLifecycleService.new(workspace).change_status(incident, attrs, changed_by: member)
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.close_incident.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      { response_action: "errors", errors: { "field_summary_block" => "Something went wrong. Please close this modal and try again." } }
    end

    def self.resolve_lead(workspace, submission)
      lead_user_id = submission.system_attrs["lead"]
      return [ nil, nil ] if lead_user_id.blank?

      lead_member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: lead_user_id,
        adapter: workspace.adapter
      )
      return [ nil, lead_provision_error ] unless lead_member

      [ lead_member, nil ]
    end
    private_class_method :resolve_lead

    # Honours the status a responder picked when the workspace has more than
    # one closed status, and falls back to the first by position when the form
    # never offered the choice.
    def self.resolve_status(workspace, submission)
      scope = workspace.incident_statuses.closed.active.ordered
      chosen = submission.system_attrs[IncidentSystemField::KEY_STATUS]

      (chosen.present? && scope.find_by(slug: chosen)) || scope.first
    end
    private_class_method :resolve_status

    def self.build_close_attrs(workspace, incident, submission, lead_member)
      system_attrs = submission.system_attrs

      attrs = {
        incident_status: resolve_status(workspace, submission),
        incident_severity: system_attrs["severity"].present? ? workspace.incident_severities.active.find_by!(slug: system_attrs["severity"]) : incident.incident_severity
      }
      attrs[:name] = system_attrs["name"] if system_attrs["name"].present?
      attrs[:summary] = system_attrs["summary"] if system_attrs["summary"].present?
      attrs[:incident_type] = workspace.incident_types.active.find_by!(slug: system_attrs["incident_type"]) if system_attrs["incident_type"].present?
      # Only the submitted fields. Values are rows now, so writing a subset
      # leaves the rest untouched without reading them back first.
      attrs[:custom_fields] = submission.custom_fields if submission.custom_fields.present?
      attrs[:lead] = lead_member if lead_member
      attrs
    end
    private_class_method :build_close_attrs

    def self.already_closed_error
      { response_action: "errors", errors: { "field_summary_block" => "This incident is already closed." } }
    end
    private_class_method :already_closed_error

    def self.lead_provision_error
      { response_action: "errors", errors: { "field_lead_block" => "Couldn't load that user's profile from Slack. Please try again in a moment." } }
    end
    private_class_method :lead_provision_error
  end
end
