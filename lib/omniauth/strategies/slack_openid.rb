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
    # `user_scope=openid,profile,email`.
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
        state = SecureRandom.hex(24)
        generated_verifier = options.pkce ? SecureRandom.hex(64) : nil
        params = deep_symbolize(options.authorize_params)
          .merge(options_for("authorize"))
          .merge(pkce_authorize_params_for(generated_verifier))
          .merge(state: state, scope: "", user_scope: "openid,profile,email")

        session["omniauth.pkce.verifier"] = generated_verifier if generated_verifier
        session["omniauth.state"] = state

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
        end

        actual_verifier = params[:code_verifier] || params["code_verifier"]
        OmniAuth.logger.info({
          event: "pkce.token_request",
          strategy: "slack_openid",
          code_present: code.present?,
          code_verifier_in_params: actual_verifier.present?,
          code_verifier_length: actual_verifier&.length,
          code_verifier_fingerprint: actual_verifier && "#{actual_verifier[0, 6]}..#{actual_verifier[-6, 6]}",
          param_keys: params.keys.map(&:to_s),
          redirect_uri: params[:redirect_uri] || params["redirect_uri"]
        }.to_json)

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

      def pkce_authorize_params_for(verifier)
        return {} unless verifier

        {
          code_challenge: options.pkce_options[:code_challenge].call(verifier),
          code_challenge_method: options.pkce_options[:code_challenge_method]
        }
      end
    end
  end
end

OmniAuth.config.add_camelization "slack_openid", "SlackOpenid"
