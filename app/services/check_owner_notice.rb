# A direct message to each admin and owner of the workspace, through the platform, saying a scheduled check paused for
# want of an owner and where to give it one, as AI account problems are told (WorkspaceAiAccountService#notify_admins!).
class CheckOwnerNotice
  def initialize(check)
    @check = check
    @workspace = check.workspace
  end

  def tell_admins!
    adapter = WorkspaceAdapter.for(@workspace)
    @workspace.workspace_memberships.admins_and_owners.current_members.where.not(platform_user_id: nil).find_each do |admin|
      adapter.post_notice(user_id: admin.platform_user_id, notice: notice)
    rescue AdapterError => error
      Rails.logger.warn({ event: "check_owner.notice_failed", check_id: @check.id, error: error.class.name }.to_json)
    end
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
