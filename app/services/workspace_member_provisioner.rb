class WorkspaceMemberProvisioner
  # user and user_profile skip the email lookup and the adapter fetch when the caller already
  # has them. user_profile takes the OIDC info shape or Slack's users.info shape. Returns nil on AdapterError.
  # A person who joined by email before using the platform here is matched by who they are, and keeps their seat.
  def self.find_or_provision!(workspace:, platform_user_id:, adapter:, user: nil, user_profile: nil)
    existing = workspace.workspace_memberships.find_by(platform_user_id: platform_user_id)
    return existing if existing

    joined = user && workspace.workspace_memberships.find_by(user: user)
    return joined.link_platform_user!(platform_user_id, plain(user_profile)) if joined

    profile = user_profile || fetch_profile(adapter, platform_user_id)

    name = pick(profile, :real_name, :name).presence ||
           pick(profile, :display_name).presence ||
           platform_user_id

    email = pick(profile, :email).presence ||
            "#{platform_user_id}@users.slack.#{workspace.platform_id}"

    user ||= begin
      found = User.find_or_initialize_by(email: email)
      found.name = name if found.name.blank?
      found.save!
      found
    end

    joined = workspace.workspace_memberships.find_by(user: user)
    return joined.link_platform_user!(platform_user_id, plain(profile)) if joined

    workspace.workspace_memberships.create!(
      user: user,
      platform_user_id: platform_user_id,
      role: :member,
      platform_data: plain(profile),
      joined_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Lost a concurrent provision race, the unique index rejected our insert. Return
    # the winner's row, or re-raise when none exists since that was a real validation failure.
    workspace.workspace_memberships.find_by(platform_user_id: platform_user_id) ||
      (user && workspace.workspace_memberships.find_by(user: user)) || raise
  rescue AdapterError => e
    Rails.logger.warn({
      event: "workspace_member_provisioner.api_error",
      workspace_id: workspace.id,
      platform_user_id: platform_user_id,
      error: e.message
    })
    nil
  end

  def self.plain(profile)
    profile.is_a?(Hash) ? profile : {}
  end
  private_class_method :plain

  def self.fetch_profile(adapter, platform_user_id)
    adapter.get_user_info(user_id: platform_user_id)
  end
  private_class_method :fetch_profile

  # Accepts both an OmniAuth::AuthHash::InfoHash and a plain hash with symbol or string keys.
  def self.pick(profile, *keys)
    keys.each do |key|
      value = profile.respond_to?(key) ? profile.public_send(key) :
              profile.is_a?(Hash) ? (profile[key] || profile[key.to_s]) : nil
      return value if value.present?
    end
    nil
  end
  private_class_method :pick
end
