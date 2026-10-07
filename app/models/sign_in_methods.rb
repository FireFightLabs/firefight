# Which ways to sign in this host offers. Slack is always there. Google and email wait for the self-serve flag and
# for the host to be set up for them.
module SignInMethods
  def self.self_serve? = FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)
  def self.google? = self_serve? && Rails.application.config.x.google_sign_in == true
  def self.email? = self_serve? && MailDelivery.configured?
end
