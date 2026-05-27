module Slack
  class AuthRevokedNotifier
    def self.notify(workspace, error_code:)
      Rails.logger.warn({
        event:        "slack.auth_revoked",
        workspace_id: workspace.id,
        platform_id:  workspace.platform_id,
        error_code:   error_code,
        detected_at:  Time.current.iso8601
      })
      # TODO: admin email / in-app notification + flag workspace for re-install.
    end
  end
end
