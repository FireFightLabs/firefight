module Slack
  # Slack has said the install is gone. Records it on the workspace so the
  # dashboard can ask for a reinstall and the token refresh stops retrying.
  # Only codes that mean "gone for good" flip the flag. invalid_auth and
  # not_authed still raise to the caller but can be transient, so they only
  # log.
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
