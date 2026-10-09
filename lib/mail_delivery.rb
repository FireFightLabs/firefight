# Outgoing mail is set from the environment, so a host that sets nothing sends nothing and offers no email sign-in.
module MailDelivery
  def self.smtp_settings(env = ENV)
    address = env["SMTP_ADDRESS"].presence
    return nil unless address

    {
      address: address,
      port: (env["SMTP_PORT"].presence || 587).to_i,
      user_name: env["SMTP_USERNAME"].presence,
      password: env["SMTP_PASSWORD"].presence,
      authentication: env["SMTP_USERNAME"].present? ? :plain : nil,
      enable_starttls_auto: true
    }.compact
  end

  # A deployed host needs a server, a sender and the dashboard's address for the links in each message.
  def self.deployed_configured?(env = ENV)
    smtp_settings(env).present? && env["MAIL_FROM"].present? && env["APP_HOST"].present?
  end

  # Read from the environment's own setting, so development and test answer too.
  def self.configured? = Rails.application.config.x.mail_configured == true

  def self.url_options(env = ENV)
    { host: env["APP_HOST"].presence || "example.com", protocol: env.fetch("APP_PROTOCOL", "https") }
  end
end
