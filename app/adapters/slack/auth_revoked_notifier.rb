module Slack
  # Only codes that mean the install is gone for good flip the flag.
  # invalid_auth and not_authed can be transient, so they only log.
  class AuthRevokedNotifier
    def self.notify(workspace, error_code:)
      Rails.logger.warn({
        event:        "slack.auth_revoked",
        workspace_id: workspace.id,
        platform_id:  workspace.platform_id,
        error_code:   error_code,
        detected_at:  Time.current.iso8601
      })
      workspace.mark_disconnected!(error_code)
    end
  end
end
