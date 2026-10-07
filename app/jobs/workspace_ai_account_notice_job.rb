# Tells a workspace's admins, once, that one of its own AI accounts ran out of credit or had its key refused, and that
# Halon moved on to the next account. A direct message to each admin, through the workspace's platform.
class WorkspaceAiAccountNoticeJob < ApplicationJob
  queue_as :default

  # Whoever may change the workspace's AI accounts.
  ADMIN_ROLES = [ WorkspaceMembership.roles[:admin], WorkspaceMembership.roles[:owner] ].freeze

  def perform(account_id, notice)
    account = WorkspaceAiAccount.find_by(id: account_id)
    return unless account

    text = self.class.text(account, notice)
    adapter = WorkspaceAdapter.for(account.workspace)
    account.workspace.workspace_memberships.where(role: ADMIN_ROLES).where.not(platform_user_id: nil).find_each do |admin|
      adapter.post_direct_message(user_id: admin.platform_user_id, text: text)
    rescue AdapterError => e
      Rails.logger.warn({ event: "ai_account.notice_failed", account_id: account.id, error: e.class.name }.to_json)
    end
    Rails.logger.info({ event: "ai_account.noticed", account_id: account.id, notice: notice }.to_json)
  end

  def self.text(account, notice)
    what = notice == WorkspaceAiAccount::NOTICE_KEY_REFUSED ? "had its key refused" : "ran out of credit"
    following = AiFunding.for(account.workspace, AiPurpose::INVESTIGATION).any?
    next_step = following ? "Halon is using the next one in the list." : "Halon has no other account to use, so it cannot answer until this is fixed."
    where = settings_link ? "Fix it under Settings, Workspace, AI accounts: #{settings_link}" : "Fix it under Settings, Workspace, AI accounts."
    "Halon's AI account \"#{account.label}\" #{what}. #{next_step} #{where}"
  end

  def self.settings_link
    host = ENV["APP_HOST"].presence
    host && Rails.application.routes.url_helpers.settings_workspace_url(host: host, protocol: ENV.fetch("APP_PROTOCOL", "https"))
  end
end
