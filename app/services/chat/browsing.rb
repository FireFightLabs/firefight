# Runs one check of a website in Halon's browser, in the run's sandbox. When the check logs in, the site's saved test login is read here and handed to the sandbox for this one run, on the command's
# input, so the password never reaches the model, the chat, the ledger or a log, and is taken out of what comes back
# should a page echo it.
module Chat::Browsing
  NO_LOGIN = "No test login is saved for %<host>s. An admin saves one under Settings, Test logins, and Halon's browser " \
             "logs in with it. Check the page without log_in, or ask an admin to add one.".freeze

  # expected_send is the request the person agreed the confirmed step sends, method and address, so a page that now
  # sends something else is stopped rather than sent. Answers what the browser saw, its screenshots still in it for the
  # caller to keep (Chat::Screenshot.record!) once it knows the step it records the check under.
  def self.run(workspace:, box_key:, check:, expected_send: nil)
    login = check.log_in ? login_for!(workspace, check) : nil
    secret = login && Integrations::SiteLogins.secret_for(workspace, login.id)
    spec = check.to_spec(expected_send: expected_send)
    spec["login"] = login_spec(login, secret) if login
    browsed = Integrations::Terminal.new(key: box_key, workspace: workspace).browse(spec)
    Chat::BrowserCheck::Answer.new(browsed.answer, check: check, region: browsed.region, login_name: login&.name, secrets: [ secret.to_h["password"] ])
  end

  # The saved login for the address's site, or Refused saying none is saved.
  def self.login_for!(workspace, check)
    Integrations::SiteLogins.for_url(workspace, check.url) || raise(Chat::BrowserCheck::Refused, format(NO_LOGIN, host: check.host))
  end

  def self.login_spec(login, secret)
    { "site_url" => login.site_url, "login_url" => login.login_url.presence || login.site_url,
      "username" => secret.to_h["username"], "password" => secret.to_h["password"] }
  end
  private_class_method :login_spec
end
