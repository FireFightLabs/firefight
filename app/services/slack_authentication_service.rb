# Service for processing Slack OAuth authentication
# Orchestrates workspace/user creation and triggers setup workflow for new installations
class SlackAuthenticationService
  # Process OAuth callback from Slack
  #
  # @param auth_hash [OmniAuth::AuthHash] OAuth response from Slack
  # @return [Hash] Result with :workspace, :user, :membership, :first_install
  def process_oauth_callback(auth_hash)
    result = Workspace.process_slack_installation(auth_hash)

    if result[:first_install]
      trigger_workspace_setup(result[:workspace], auth_hash.uid)
    end

    result
  end

  private

  def trigger_workspace_setup(workspace, installer_user_id)
    Rails.logger.info({
      event: "slack_authentication.workspace_setup_triggered",
      message: "Triggering workspace setup workflow for first installation",
      workspace_id: workspace.id,
      installer_user_id: installer_user_id
    })

    SlackWorkspaceSetupWorkflow.start!(
      workspace,
      context: { installer_user_id: installer_user_id }
    )
  end
end
