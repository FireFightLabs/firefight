# Every sign-in method ends here, so which person a sign-in reaches is decided in one place. A provider's own account
# id wins first, then an email the provider has verified. An email alone never moves an account that already has a
# matching identity, so changing your address at Google or Slack keeps you where you were.
class AuthenticationService
  SIGNED_IN = :signed_in
  UNVERIFIED_EMAIL = :unverified_email
  NO_ACCOUNT = :no_account

  Claims = Data.define(:provider, :uid, :email, :email_verified, :name, :avatar_url) do
    def initialize(provider:, uid:, email:, email_verified:, name: nil, avatar_url: nil)
      super(
        provider: provider,
        uid: uid.to_s,
        email: email.to_s.strip.downcase.presence,
        email_verified: ActiveModel::Type::Boolean.new.cast(email_verified) == true,
        name: name.presence,
        avatar_url: avatar_url.presence
      )
    end

    def verified_email = email_verified ? email : nil
  end

  Result = Data.define(:status, :user, :identity) do
    def signed_in? = status == SIGNED_IN
    def unverified_email? = status == UNVERIFIED_EMAIL
    def no_account? = status == NO_ACCOUNT
  end

  # create_user makes a person for a verified email nobody holds yet. require_verified_email refuses an unverified
  # email even from an account already linked. refresh_profile overwrites the name and avatar on every sign-in rather
  # than only filling blanks.
  def sign_in_with(claims, create_user: false, require_verified_email: false, refresh_profile: false)
    return unverified if require_verified_email && !claims.verified_email

    identity = UserIdentity.find_by(provider: claims.provider, uid: claims.uid)
    return returning(identity, claims, refresh_profile) if identity
    return unverified unless claims.verified_email

    user = User.find_by(email: claims.verified_email)
    user ||= create_user!(claims) if create_user
    return Result.new(status: NO_ACCOUNT, user: nil, identity: nil) unless user

    link(user, claims, refresh_profile)
  end

  private

  def unverified = Result.new(status: UNVERIFIED_EMAIL, user: nil, identity: nil)

  def returning(identity, claims, refresh_profile)
    identity.update!(email: claims.email, email_verified: claims.email_verified, last_used_at: Time.current)
    update_profile(identity.user, claims, refresh_profile)
    Result.new(status: SIGNED_IN, user: identity.user, identity: identity)
  end

  def link(user, claims, refresh_profile)
    had_methods = user.identities.exists?
    identity = UserIdentity.transaction(requires_new: true) do
      user.identities.create!(
        provider: claims.provider, uid: claims.uid, email: claims.email,
        email_verified: claims.email_verified, last_used_at: Time.current
      )
    end
    update_profile(user, claims, refresh_profile)
    notify_added(identity) if had_methods
    Result.new(status: SIGNED_IN, user: user, identity: identity)
  rescue ActiveRecord::RecordNotUnique
    # The same account signed in twice at once and the other request linked it first.
    returning(UserIdentity.find_by!(provider: claims.provider, uid: claims.uid), claims, refresh_profile)
  end

  def create_user!(claims)
    User.transaction(requires_new: true) do
      User.create!(email: claims.verified_email, name: claims.name || claims.verified_email, avatar_url: claims.avatar_url)
    end
  rescue ActiveRecord::RecordNotUnique
    User.find_by!(email: claims.verified_email)
  end

  def update_profile(user, claims, refresh_profile)
    if refresh_profile
      user.update!(name: claims.name || claims.email || user.name, avatar_url: claims.avatar_url)
    else
      user.update!(name: user.name.presence || claims.name, avatar_url: user.avatar_url.presence || claims.avatar_url)
    end
  end

  def notify_added(identity)
    return unless MailDelivery.configured?

    SignInMailer.new_method(identity).deliver_later
  end
end
