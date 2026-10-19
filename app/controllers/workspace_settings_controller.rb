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
      **allowance_props,
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
    # The install starts only from a form posted with this page's token, so the answer is a page that posts one.
    render "auth/continue", layout: "oauth", locals: { action: install_slack_app_path }
  end

  private

  # What Halon may do without asking (AllowancesController), and what an entry can name.
  def allowance_props
    tools = current_workspace.switched_on_tools
    {
      allowances: AllowanceSerializer.many(current_workspace.allowances.with_usage_counts.includes(:environment, :created_by, :integration, action: :source).order(:created_at)),
      allowanceCapabilities: AllowanceChoiceSerializer.many(Ability::Allowance.capability_choices(current_workspace, tools: tools)),
      allowanceTools: AllowanceChoiceSerializer.many(Ability::Allowance.tool_choices(current_workspace, tools: tools)),
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries)
    }
  end

  # A new code fix budget is named, since it is what every fix may spend from now on, and so is whether Halon asks
  # before a safe change, since it changes what every chat does next.
  def updated_words(before)
    changed = current_workspace.settings.reject { |key, value| before[key] == value }.keys
    named = [ (budget_words if changed.include?(:code_fix_budget_cents)), (safe_change_words if changed.include?(:safe_changes_without_asking)) ].compact
    return UPDATED if named.empty?

    (changed - NAMED_SETTINGS).empty? ? named.join(" ") : [ UPDATED, *named ].join(" ")
  end

  NAMED_SETTINGS = %i[code_fix_budget_cents safe_changes_without_asking].freeze

  def budget_words = "Code fix budget was set to #{current_workspace.shown_code_fix_budget}."

  def safe_change_words
    current_workspace.safe_changes_without_asking? ? "Halon makes safe changes without asking." : "Halon now asks before safe changes."
  end
end
