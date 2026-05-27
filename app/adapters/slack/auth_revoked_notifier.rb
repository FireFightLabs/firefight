module Slack
  # Surfaces terminal Slack auth failures so an operator can act before the
  # workspace's experience degrades silently. Today: structured warn log.
  # Once a workspace-admin notifier exists, this hooks into it the same way
  # Webhooks::DeactivationNotifier will.
  class AuthRevokedNotifier
    def self.notify(workspace, error_code:)
      Rails.logger.warn({
        event:        "slack.auth_revoked",
        workspace_id: workspace.id,
        platform_id:  workspace.platform_id,
        error_code:   error_code,
        detected_at:  Time.current.iso8601
      })
      # TODO: send admin email / in-app notification + flag the workspace as
      # needing re-install once we have a workspace-admin notifier.
    end
  end
end
