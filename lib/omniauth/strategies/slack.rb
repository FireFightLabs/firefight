require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class Slack < OmniAuth::Strategies::OAuth2
      option :name, "slack"

      option :client_options, {
        site: "https://slack.com",
        authorize_url: "https://slack.com/oauth/v2/authorize",
        token_url: "https://slack.com/api/oauth.v2.access"
      }

      # Enable PKCE (Proof Key for Code Exchange, RFC 7636).
      # Defense-in-depth on top of client_secret: prevents an attacker who
      # intercepts the authorization code from redeeming it without the
      # original code_verifier.
      option :pkce, true

      # Unique identifier for the user
      uid { raw_info.dig("authed_user", "id") }

      # Basic info about the user and team
      info do
        {
          name: user_info.dig("user", "real_name") || user_info.dig("user", "name"),
          email: user_info.dig("user", "profile", "email"),
          image: user_info.dig("user", "profile", "image_512"),
          team_id: raw_info.dig("team", "id"),
          team_name: raw_info.dig("team", "name")
        }
      end

      # Extra data including raw response
      extra do
        {
          raw_info: raw_info,
          team_info: team_info,
          user_info: user_info
        }
      end

      # Raw OAuth response from Slack
      def raw_info
        @raw_info ||= access_token.params
      end

      # Team/workspace information
      def team_info
        @team_info ||= raw_info["team"] || {}
      end

      # Detailed user information
      def user_info
        @user_info ||= begin
          user_id = raw_info.dig("authed_user", "id")
          token = raw_info.dig("authed_user", "access_token") || access_token.token

          response = access_token.client.request(:get, "https://slack.com/api/users.info",
            params: { user: user_id },
            headers: { "Authorization" => "Bearer #{token}" }
          )

          JSON.parse(response.body)
        rescue => e
          Rails.logger.error "Failed to fetch Slack user info: #{e.message}"
          { "user" => {} }
        end
      end

      # Override callback_url to ensure it's correct
      def callback_url
        full_host + callback_path
      end

      # Override build_access_token to pass the PKCE code_verifier per-request
      # instead of relying on omniauth-oauth2's auto-handling, which mutates
      # shared strategy options across requests and can leak verifiers between
      # concurrent or rapid-fire auth attempts.
      def build_access_token
        code = request.params["code"]
        params = { redirect_uri: callback_url }.merge(token_params.to_hash(symbolize_keys: true))

        if options.pkce
          verifier = session.delete("omniauth.pkce.verifier")
          params[:code_verifier] = verifier if verifier
        end

        client.auth_code.get_token(code, params, deep_symbolize(options.auth_token_params))
      end
    end
  end
end

# Register the strategy with OmniAuth
OmniAuth.config.add_camelization "slack", "Slack"
