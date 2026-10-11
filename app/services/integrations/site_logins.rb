module Integrations
  # The test logins an admin saved for Halon's browser, the one way in for anything outside the integrations layer. A
  # login is a connection of the provider that keeps them (IntegrationProvider.test_logins), written by
  # Integration::SiteLogin. What is read back never holds the password, except secret_for, for the browser's own run.
  module SiteLogins
    # One saved login as anything may see it, never with its password.
    Login = Data.define(:id, :name, :site_url, :login_url, :username, :password_hint)

    # Every saved login of the workspace's live rows, in name order.
    def self.listed(workspace)
      Integration::SiteLogin.all_in(workspace).select { |login| login.integration.disabled_at.nil? }.map { |login| shown(login) }
    end

    # The login saved for the site an address is on, by its host, case and a leading www aside, or nil.
    def self.for_url(workspace, url)
      host = Integration::SiteLogin.host_of(url)
      host && listed(workspace).find { |login| Integration::SiteLogin.host_of(login.site_url) == host }
    end

    # The username and password of one login, only for Halon's browser, which hands them to the sandbox for the one run
    # that signs in and never to the model, a chat, the ledger or a log. nil when the login is gone.
    def self.secret_for(workspace, login_id)
      login = Integration::SiteLogin.all_in(workspace).find { |each| each.id.to_s == login_id.to_s && each.integration.disabled_at.nil? }
      row = login&.environment_row
      password = row && pack.password_of(ConnectionSettings.of(row))
      return unless password

      { "username" => login.username.to_s, "password" => password }
    end

    # Why a password cannot be saved, or nil.
    def self.password_refusal(password) = Credentials.refusal(key, { pack::PASSWORD => password })

    def self.keep_password!(environment_row, password) = Credentials.store!(environment_row, { pack::PASSWORD => password })

    def self.shown(login)
      Login.new(id: login.id, name: login.integration.name, site_url: login.site_url, login_url: login.login_url.presence,
                username: login.username, password_hint: login.password_hint)
    end

    def self.key = IntegrationProvider.test_logins.key

    def self.pack = NativePack.for(key)
    private_class_method :shown, :key, :pack
  end
end
