module Integrations
  # Builds outbound auth headers for a wired environment. Static tokens pass
  # through; OAuth credentials rotate themselves when close to expiry and the
  # rotation is persisted before it is used.
  class Credentials
    def self.headers_for(environment_row)
      return {} unless environment_row

      credentials = environment_row.oauth
      return environment_row.request_headers if credentials.blank?

      credentials = environment_row.rotate_oauth!(OauthClient.refresh(credentials)) if OauthClient.stale?(credentials)
      { "Authorization" => "Bearer #{OauthClient.access_token(credentials)}" }
    end
  end
end
