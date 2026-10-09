# The webhook an issue tracker sends its changes to Firefight through, kept on the row the tracker connection is called
# through (Workspace::IssueSync#issue_webhook_row). Firefight keeps the secret when it registered the webhook itself, and
# an admin pastes it under Settings, Workspace when the tracker is set up by hand.
module IntegrationEnvironment::IssueWebhook
  extend ActiveSupport::Concern

  included do
    encrypts :issue_webhook_secret
    normalizes :issue_webhook_secret, with: ->(value) { value.to_s.strip.presence }
  end

  def issue_webhook_registered? = issue_webhook_id.present?

  def issue_webhook_secret_set? = issue_webhook_secret.present?

  # Where Firefight keeps a webhook it registered, or nothing once it is gone.
  def issue_webhook_registered!(webhook)
    update!(issue_webhook_id: webhook&.id, issue_webhook_secret: webhook&.secret, issue_webhook_expires_at: webhook&.expires_at, issue_webhook_error: nil)
  end

  def issue_webhook_failed!(words) = update_columns(issue_webhook_error: words.to_s.truncate(500), updated_at: Time.current)

  # A secret is for the tracker it was copied from, so choosing another one forgets it and the webhook with it.
  def forget_issue_webhook!
    update!(issue_webhook_secret: nil, issue_webhook_id: nil, issue_webhook_expires_at: nil, issue_webhook_error: nil)
  end
end
