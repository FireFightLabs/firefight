# A direct message to each admin and owner of the workspace, through the platform, saying a scheduled check paused for
# want of an owner and where to give it one, as AI account problems are told (WorkspaceAiAccountService#notify_admins!).
class CheckOwnerNotice
  def initialize(check)
    @check = check
    @workspace = check.workspace
  end

  # A message that can never land: nobody there, a platform the workspace disconnected, or one that took Firefight's access.
  FOR_GOOD = [ AdapterError::NotFound, AdapterError::AuthRevoked, AdapterError::NotConnected ].freeze

  # Answers whether to try again: no admin was told, and some failure may pass. A workspace with no admin on the platform,
  # or only messages that can never land, has nothing to try again for.
  def tell_admins!
    adapter = WorkspaceAdapter.for(@workspace)
    told = 0
    passing = 0
    @workspace.workspace_memberships.admins_and_owners.current_members.where.not(platform_user_id: nil).find_each do |admin|
      adapter.post_notice(user_id: admin.platform_user_id, notice: notice)
      told += 1
    rescue AdapterError => error
      passing += 1 unless FOR_GOOD.any? { |kind| error.is_a?(kind) }
      Rails.logger.warn({ event: "check_owner.notice_failed", check_id: @check.id, error: error.class.name }.to_json)
    end
    told.zero? && passing.positive?
  end

  private

  def notice
    link = monitoring_link
    PlatformAdapter::Notice.new(
      title: @check.paused_because, body: "An admin can take it over or give it to another member on the Monitoring page.",
      link_label: "Open Monitoring", link_url: link, fallback: [ @check.paused_because, link ].compact.join(" ")
    )
  end

  def monitoring_link
    options = AppUrl.options
    options && Rails.application.routes.url_helpers.halon_monitoring_url(**options)
  end
end
