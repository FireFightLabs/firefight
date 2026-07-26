module Integrations
  # Builds outbound auth headers for a wired environment. Static tokens pass
  # through; OAuth credentials refresh themselves when close to expiry and
  # persist the rotated tokens back onto the row.
  class Credentials
    REFRESH_MARGIN = 60.seconds

    def self.headers_for(environment_row)
      return {} unless environment_row

      oauth = environment_row.credentials_hash["oauth"]
      return environment_row.request_headers unless oauth

      { "Authorization" => "Bearer #{fresh_access_token(environment_row, oauth)}" }
    end

    def self.fresh_access_token(environment_row, oauth)
      expires_at = oauth["expires_at"].presence && Time.zone.parse(oauth["expires_at"])
      fresh = expires_at.nil? || expires_at > REFRESH_MARGIN.from_now
      return oauth["access_token"] if fresh || oauth["refresh_token"].blank?

      rotated = OauthClient.refresh(
        token_endpoint: oauth["token_endpoint"], refresh_token: oauth["refresh_token"],
        client_id: oauth["client_id"], client_secret: oauth["client_secret"], resource: oauth["resource"]
      )
      merged = oauth.merge(rotated) { |_key, old, new| new.presence || old }
      environment_row.update!(credentials: environment_row.credentials_hash.merge("oauth" => merged).to_json)
      merged["access_token"]
    end
  end
end
