class WorkspaceMemberProvisioner
  # Ensures a WorkspaceMembership exists for the given Slack user. Returns the
  # existing membership if one is already present; otherwise creates a user +
  # membership row.
  #
  # @param workspace        [Workspace]
  # @param platform_user_id [String] Slack user ID (e.g. "U09...")
  # @param adapter          [WorkspaceAdapter] used to fetch profile when not supplied
  # @param user             [User, nil] Pre-identified user (OIDC path). When
  #   provided, skips the User.find_or_initialize_by(email:) lookup.
  # @param user_profile     [Hash, nil] Pre-fetched profile (name/email/image).
  #   When provided, skips the `adapter.get_user_info` call. Keys may be
  #   symbols or strings; supports both OIDC's `auth_hash.info` shape and
  #   Slack's `users.info` profile shape.
  # @return [WorkspaceMembership, nil] nil on AdapterError.
  def self.find_or_provision!(workspace:, platform_user_id:, adapter:, user: nil, user_profile: nil)
    existing = workspace.workspace_memberships.find_by(platform_user_id: platform_user_id)
    return existing if existing

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

    workspace.workspace_memberships.create!(
      user: user,
      platform_user_id: platform_user_id,
      role: :member,
      platform_data: profile.is_a?(Hash) ? profile : {},
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

  # Retrieves the Slack profile hash via adapter, normalizing Slack's nested
  # `{ user: { profile: {...} } }` shape into a flat profile hash.
  def self.fetch_profile(adapter, platform_user_id)
    response  = adapter.get_user_info(user_id: platform_user_id)
    slack_user = response[:user] || response["user"] || {}
    slack_user[:profile] || slack_user["profile"] || {}
  end
  private_class_method :fetch_profile

  # Reads the first present value for any of the given keys in the profile hash,
  # trying symbol and string variants. Accepts both OmniAuth::AuthHash::InfoHash
  # (responds to symbol methods) and plain hashes.
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
