require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class SlackOpenidAccessToken < ::OAuth2::AccessToken
      def self.from_hash(client, hash)
        params = hash.dup
        user_token = params.dig("authed_user", "access_token") || params.dig(:authed_user, :access_token)
        new(client, user_token, params)
      end
    end

    # Slack sign-in strategy. Uses OAuth v2 with an empty bot `scope` and
    # `user_scope=openid,profile,email` — the same approach incident.io uses.
    # This triggers Slack's native workspace picker and consent screen, returns
    # user identity only, and does NOT install a bot.
    #
    # Pairs with the regular `slack` strategy: this one establishes user
    # identity, the other handles bot installation.
    class SlackOpenid < OmniAuth::Strategies::OAuth2
      option :name, "slack_openid"

      option :client_options, {
        site: "https://slack.com",
        authorize_url: "https://slack.com/oauth/v2/authorize",
        token_url: "https://slack.com/api/oauth.v2.access"
      }

      # Enable PKCE (Proof Key for Code Exchange, RFC 7636).
      # Defense-in-depth on top of client_secret for the OIDC sign-in flow.
      option :pkce, true

      def client
        ::OAuth2::Client.new(
          options.client_id,
          options.client_secret,
          deep_symbolize(options.client_options).merge(access_token_class: SlackOpenidAccessToken)
        )
      end

      def authorize_params
        params = super.merge(scope: "", user_scope: "openid,profile,email")
        verifier = session["omniauth.pkce.verifier"]
        OmniAuth.logger.info({
          event: "pkce.authorize",
          strategy: "slack_openid",
          verifier_present: verifier.present?,
          verifier_length: verifier&.length,
          verifier_fingerprint: verifier && "#{verifier[0, 6]}..#{verifier[-6, 6]}",
          challenge_present: params[:code_challenge].present?,
          challenge_fingerprint: params[:code_challenge] && "#{params[:code_challenge][0, 6]}..#{params[:code_challenge][-6, 6]}",
          challenge_method: params[:code_challenge_method],
          state_present: session["omniauth.state"].present?
        }.to_json)
        params
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
          OmniAuth.logger.info({
            event: "pkce.token_exchange",
            strategy: "slack_openid",
            verifier_present: verifier.present?,
            verifier_length: verifier&.length,
            verifier_fingerprint: verifier && "#{verifier[0, 6]}..#{verifier[-6, 6]}",
            code_present: code.present?,
            redirect_uri: callback_url,
            state_match: session["omniauth.state"].present?
          }.to_json)
        end

        client.auth_code.get_token(code, params, deep_symbolize(options.auth_token_params))
      end

      uid { raw_info["sub"] }

      info do
        {
          name:      raw_info["name"],
          email:     raw_info["email"],
          image:     raw_info["picture"],
          team_id:   raw_info["https://slack.com/team_id"],
          team_name: raw_info["https://slack.com/team_name"]
        }
      end

      extra do
        { raw_info: raw_info }
      end

      def raw_info
        @raw_info ||= begin
          response = access_token.client.request(
            :get,
            "https://slack.com/api/openid.connect.userInfo",
            headers: { "Authorization" => "Bearer #{access_token.token}" }
          )
          JSON.parse(response.body)
        end
      end

      def callback_url
        full_host + callback_path
      end
    end
  end
end

OmniAuth.config.add_camelization "slack_openid", "SlackOpenid"
