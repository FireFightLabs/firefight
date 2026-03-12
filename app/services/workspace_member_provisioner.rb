class WorkspaceMemberProvisioner
  def self.find_or_provision!(workspace:, platform_user_id:, adapter:)
    existing = workspace.workspace_memberships.find_by(platform_user_id: platform_user_id)
    return existing if existing

    user_info = adapter.get_user_info(user_id: platform_user_id)
    slack_user = user_info[:user] || user_info["user"] || {}
    profile = slack_user[:profile] || slack_user["profile"] || {}

    name = profile[:real_name].presence ||
           profile[:display_name].presence ||
           slack_user[:name].presence ||
           platform_user_id

    email = profile[:email].presence ||
            "#{platform_user_id}@users.slack.#{workspace.platform_id}"

    user = User.find_or_initialize_by(email: email)
    user.name = name if user.name.blank?
    user.save!

    workspace.workspace_memberships.create!(
      user: user,
      platform_user_id: platform_user_id,
      role: :member,
      platform_data: profile,
      joined_at: Time.current
    )
  rescue AdapterError => e
    Rails.logger.warn({
      event: "workspace_member_provisioner.api_error",
      workspace_id: workspace.id,
      platform_user_id: platform_user_id,
      error: e.message
    })
    nil
  end
end
