# Tells the people running Firefight when a workspace is created and when it connects its chat platform, on the
# team webhook. Nothing is enqueued when the webhook is unset, and a failure is logged, never shown to the person.
class SignupNotificationService
  DeliveryFailed = TeamWebhook::DeliveryFailed

  WORKSPACE_CREATED = "workspace.created".freeze
  CHAT_CONNECTED = "workspace.chat_connected".freeze
  EVENTS = [ WORKSPACE_CREATED, CHAT_CONNECTED ].freeze

  SIGN_UP_METHODS = {
    UserIdentity::GOOGLE => "Google",
    UserIdentity::EMAIL => "an email link",
    UserIdentity::SLACK => "Slack"
  }.freeze

  def self.configured? = TeamWebhook.configured?

  # Enqueued once the surrounding transaction commits, so the job never reads a workspace that rolled back, and an
  # enqueue that fails never fails the sign-up.
  def self.announce(event, workspace, membership, sign_up_method: nil)
    return unless configured?

    ActiveRecord.after_all_transactions_commit do
      SignupNotificationJob.perform_later(event, workspace.id, membership.id, sign_up_method)
    rescue StandardError => e
      Rails.logger.warn({ event: "signup_notification.enqueue_failed", workspace_id: workspace.id, error: e.class.name, message: e.message.truncate(200) }.to_json)
    end
  end

  def notify(event, workspace, member, sign_up_method: nil)
    TeamWebhook.post!(payload(event, workspace, member, sign_up_method))
    Rails.logger.info({ event: "signup_notification.sent", notification: event, workspace_id: workspace.id }.to_json)
  end

  private

  def payload(event, workspace, member, sign_up_method)
    {
      text: text(event, workspace, member, sign_up_method),
      event: event,
      workspace_name: workspace.name,
      platform: workspace.platform,
      platform_id: workspace.platform_id,
      installer_name: member.display_name,
      installer_email: member.email,
      sign_up_method: sign_up_method,
      created_at: workspace.created_at.utc.iso8601,
      installed_at: workspace.installed_at&.utc&.iso8601
    }
  end

  def text(event, workspace, member, sign_up_method)
    case event
    when WORKSPACE_CREATED
      method = SIGN_UP_METHODS[sign_up_method]
      "New workspace: #{workspace.name}, created by #{member.display_name} (#{member.email})#{" with #{method}" if method}"
    when CHAT_CONNECTED
      "#{workspace.name} connected #{Platforms.display_name(workspace.platform)} (#{workspace.adapter.team_label})"
    else
      raise ArgumentError, "Unknown signup notification #{event}"
    end
  end
end
