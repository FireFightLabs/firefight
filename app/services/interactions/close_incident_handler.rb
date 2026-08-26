module Interactions
  class CloseIncidentHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      return already_closed_error(workspace) if incident.closed?

      submission = workspace.adapter.parse_form_submission(
        form_slug: IncidentForm::SLUG_RESOLVE,
        values: interaction.values,
        incident: incident
      )

      if submission.errors.any?
        return workspace.adapter.form_error_response(submission.first_error_field_key, submission.errors.first)
      end

      form = IncidentFormSubmission.new(
        workspace,
        incident: incident,
        form_slug: IncidentForm::SLUG_RESOLVE,
        system_attrs: submission.system_attrs,
        custom_fields: submission.custom_fields,
        visible_system_keys: submission.visible_system_keys
      )

      lead_member, lead_error = resolve_lead(workspace, form)
      return lead_error if lead_error

      attrs = form.attributes
      attrs[:lead] = lead_member if lead_member

      IncidentLifecycleService.new(workspace).change_status(incident, attrs, changed_by: member)
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata)

      nil
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.close_incident.record_not_found", error: e.message })
      Interactions::ModalCleanup.delete_temp_message(workspace, metadata) if workspace && metadata
      workspace.adapter.form_error_response(IncidentSystemField::KEY_SUMMARY, "Something went wrong. Please close this modal and try again.")
    end

    # Slack hands over a platform user id, so the person may not have a
    # membership row yet. Only this entry point knows that, which is why the
    # shared submission hands back the raw value rather than a member.
    def self.resolve_lead(workspace, form)
      lead_user_id = form.lead_value
      return [ nil, nil ] if lead_user_id.blank?

      lead_member = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: workspace,
        platform_user_id: lead_user_id,
        adapter: workspace.adapter
      )
      return [ nil, lead_provision_error(workspace) ] unless lead_member

      [ lead_member, nil ]
    end
    private_class_method :resolve_lead

    def self.already_closed_error(workspace)
      workspace.adapter.form_error_response(IncidentSystemField::KEY_SUMMARY, "This incident is already closed.")
    end
    private_class_method :already_closed_error

    def self.lead_provision_error(workspace)
      workspace.adapter.form_error_response(IncidentSystemField::KEY_LEAD, "Couldn't load that user's profile from Slack. Please try again in a moment.")
    end
    private_class_method :lead_provision_error
  end
end
