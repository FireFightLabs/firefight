# Transcript access is here rather than on Permissions on purpose. A grant says who
# may ask, this says whether the conversation is readable at all.
class WorkspaceSettingsController < InertiaController
  include AiAccountProps

  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: %i[update reinstall_slack]

  NOT_CONNECTED_MESSAGE = "Slack is not connected to this workspace yet. Connect it first.".freeze
  UPDATED = "Workspace settings were updated.".freeze

  def show
    render inertia: "settings/workspace", props: {
      settings: WorkspaceSettingsSerializer.one(current_workspace),
      issueWebhookUrl: current_workspace.issue_webhook_token && api_v1_issue_events_url(current_workspace.issue_webhook_token),
      workflowRunRetentionDays: current_workspace.workflow_run_retention_days,
      **ai_account_props
    }
  end

  # A blank retention casts to null, which means keep everything.
  def update
    before = current_workspace.settings
    IssueSyncService.new(current_workspace).update_settings!(params.permit(*Workspace::Settings::PERMITTED), by: current_membership)

    redirect_to settings_workspace_path, notice: updated_words(before)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end

  # Runs the Slack install again for the team already connected, so new scopes are granted without disconnecting. The
  # install callback reads reinstalling_workspace_id and refreshes this workspace, never creating one.
  def reinstall_slack
    return redirect_to(settings_workspace_path, alert: NOT_CONNECTED_MESSAGE) unless current_workspace.chat_connected?

    session.delete(:connecting_workspace_id)
    session[:reinstalling_workspace_id] = current_workspace.id
    session[:pending_user_id] = current_user.id
    session[:pending_team_id] = current_workspace.platform_id
    session[:pending_team_name] = current_workspace.chat_team_name
    request.inertia? ? inertia_location(install_slack_app_path) : redirect_to(install_slack_app_path)
  end

  private

  # A new code fix budget is named, since it is what every fix may spend from now on.
  def updated_words(before)
    changed = current_workspace.settings.reject { |key, value| before[key] == value }.keys
    return UPDATED unless changed.include?(:code_fix_budget_cents)

    budget = "Code fix budget was set to #{current_workspace.shown_code_fix_budget}."
    changed == [ :code_fix_budget_cents ] ? budget : "#{UPDATED} #{budget}"
  end
end
