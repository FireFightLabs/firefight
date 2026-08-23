# Value object returned by `SlackAuthenticationService` describing what should
# happen after an OAuth or OIDC callback. The controller maps the outcome to
# session writes + redirects without knowing the decision logic.
class AuthOutcome
  attr_reader :type, :membership, :user, :team_id, :team_name, :message, :first_install

  # message is optional, a plain returning sign-in needs no announcing.
  def self.signed_in(membership:, message: nil, first_install: false)
    new(:signed_in, membership: membership, message: message, first_install: first_install)
  end

  def self.install_needed(user:, team_id:, team_name:)
    new(:install_needed, user: user, team_id: team_id, team_name: team_name)
  end

  def self.invite_required(message:)
    new(:invite_required, message: message)
  end

  def signed_in?      = type == :signed_in
  def install_needed? = type == :install_needed
  def invite_required? = type == :invite_required
  def first_install?  = first_install

  private

  def initialize(type, membership: nil, user: nil, team_id: nil, team_name: nil, message: nil, first_install: false)
    @type          = type
    @membership    = membership
    @user          = user
    @team_id       = team_id
    @team_name     = team_name
    @message       = message
    @first_install = first_install
  end
end
