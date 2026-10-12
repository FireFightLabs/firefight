module Integrations
  module Packs
    # What Firefight's own Linear OAuth application adds to a connection it made. The app is installed with actor=app
    # (linear.app/developers/oauth-actor-authorization), so its token acts as the app's own user in the organization that
    # installed it, whose id is kept as the connection's installation. Linear's hosted MCP server takes that token
    # (linear.app/docs/mcp, FAQ), so the connection is an MCP connection and every tool is the server's
    # (IntegrationProvider::App#mcp). This pack offers no tools of its own. It checks the token acts as the app, answers
    # the installation contract (Integrations::Installations), and says the connection's issue changes arrive at the
    # OAuth application's own webhook, since an app installed this way may not hold admin (linear.app/developers/agents,
    # Admin) and so cannot create webhooks. Every call is LinearApi's.
    class Linear < NativePack
      ACTS_AS_A_PERSON = "Firefight's Linear app acts as the person who connected it, so it cannot be assigned issues or mentioned, and it stops " \
                         "when they leave Linear. Reconnect it, and have a Linear admin approve the install, so it acts as itself.".freeze

      APP_WEBHOOK_UNSET = "Firefight cannot receive Linear's changes or mentions until whoever runs Firefight sets the app's webhook " \
                          "signing secret.".freeze

      # The installation is learned here, on connecting and with every check, so a reconnect that installed the app in
      # another organization follows it. An app connection hears of changes and mentions only at the app's own webhook,
      # which exists only once the deployment has its signing secret (MapEvents.app_secret).
      def self.check_app!(environment_row)
        actor = LinearApi.new(Credentials.headers_for(environment_row)).actor.to_h
        raise Error, ACTS_AS_A_PERSON unless actor["app"]

        organization = actor.dig("organization", "id")
        Installations.connected!(environment_row, organization) if organization.present? && environment_row.installation_id != organization
        raise Error, APP_WEBHOOK_UNSET if MapEvents.app_secret(environment_row.integration.provider).blank?
      rescue LinearApi::Error => error
        raise Error, error.message
      end

      # What Linear says of the installation now. A token Linear no longer takes means the app was removed, and an app no
      # team shares anything with reaches nothing.
      def self.installation(environment_row)
        actor = LinearApi.new(Credentials.headers_for(environment_row)).actor.to_h
        organization = actor["organization"].to_h
        page = "https://linear.app/#{organization['urlKey']}/settings/integrations" if organization["urlKey"].present?
        Installations::Installation.new(state: (Installations::EMPTIED if actor["teams"].blank?), account: organization["name"], page: page)
      rescue LinearApi::Unauthorized, OauthClient::SignInEnded
        Installations::Installation.new(state: Installations::REMOVED)
      end

      # Revoking the app's token removes the app from the organization (linear.app/developers/oauth-2-0-authentication,
      # Revoke an access token).
      def self.uninstall(environment_row) = LinearApi.revoke(OauthClient.access_token(environment_row.oauth))

      def self.forget_access(_environment_row) = nil

      def self.app_name = "Linear app"

      def self.reach_name = "teams"

      # Linear grants an app every scope it asked for at install, so a tool never lacks one.
      def self.missing_access(_environment_row, _tool_name) = []

      # A connection installed as the app has its issue changes sent to the app's own webhook, so nothing is registered
      # or pasted for it.
      def self.issue_changes_through_app?(environment_row) = environment_row.present? && environment_row.installation_id.present?
    end
  end
end
