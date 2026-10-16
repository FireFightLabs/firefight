class WorkspaceMemberProvisioner
  # The platform says this person is not one of the workspace's own, such as a guest or someone from another
  # organisation reached through a shared channel. The message is the platform's sentence for them.
  class Refused < StandardError; end

  # Everyone who only needs to know whether someone is a member asks this. A person the platform refuses is nil, as an
  # unreadable profile is.
  def self.find_or_provision!(**)
    admit!(**)
  rescue Refused
    nil
  end

  # The sentence a person is refused with, or nil once they are a member, provisioned on the way. For a way in that
  # tells the person why.
  def self.refusal(**)
    admit!(**)
    nil
  rescue Refused => e
    e.message
  end

  # user skips the email lookup when the caller already knows who signed in, and user_profile names them. The platform
  # is still asked whether the person belongs to the workspace. A person who joined by email before using the platform
  # here is matched by who they are, and by email only when the platform confirmed it. Returns nil on AdapterError.
  def self.admit!(workspace:, platform_user_id:, adapter:, user: nil, user_profile: nil)
    existing = workspace.workspace_memberships.find_by(platform_user_id: platform_user_id)
    return still_admitted!(existing, adapter) if existing

    joined = user && workspace.workspace_memberships.find_by(user: user)
    return joined.link_platform_user!(platform_user_id, plain(user_profile)) if joined

    profile = fetch_profile(adapter, platform_user_id)
    refused = adapter.member_refusal(profile: profile)
    raise Refused, refused if refused

    named = user_profile || profile
    name = pick(named, :real_name, :name).presence ||
           pick(named, :display_name).presence ||
           platform_user_id

    confirmed = pick(profile, :email_confirmed) == true
    email = (pick(profile, :email).presence if confirmed) ||
            "#{platform_user_id}@users.slack.#{workspace.platform_id}"

    user ||= begin
      found = User.find_or_initialize_by(email: email)
      found.name = name if found.name.blank?
      found.save!
      found
    end

    joined = workspace.workspace_memberships.find_by(user: user)
    return joined.link_platform_user!(platform_user_id, plain(user_profile || profile)) if joined

    workspace.workspace_memberships.create!(
      user: user,
      platform_user_id: platform_user_id,
      role: :member,
      platform_data: plain(user_profile || profile),
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

  # A member whose saved profile says they would be refused today is asked about again, so a guest made a full member
  # gets in and one who still is a guest stays out. Everyone else is let in without asking the platform.
  def self.still_admitted!(membership, adapter)
    return membership unless refused_when_saved?(membership, adapter)

    profile = fetch_profile(adapter, membership.platform_user_id)
    membership.update!(platform_data: plain(profile))
    refused = adapter.member_refusal(profile: profile)
    raise Refused, refused if refused

    membership
  end
  private_class_method :still_admitted!

  # A workspace whose platform is gone cannot say, and its members keep their seats.
  def self.refused_when_saved?(membership, adapter)
    return false if membership.platform_data.blank?

    adapter.member_refusal(profile: membership.platform_data).present?
  rescue AdapterError
    false
  end
  private_class_method :refused_when_saved?

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
              profile.is_a?(Hash) ? (profile[key].nil? ? profile[key.to_s] : profile[key]) : nil
      return value unless value.nil? || value == ""
    end
    nil
  end
  private_class_method :pick
end
