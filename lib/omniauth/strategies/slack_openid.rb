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

        log_pkce_authorize(generated_verifier, params)
        params
      end

      # Override build_access_token to pass the PKCE code_verifier per-request
      # instead of relying on omniauth-oauth2's auto-handling, which mutates
      # shared strategy options across requests and can leak verifiers between
      # concurrent or rapid-fire auth attempts.
      def build_access_token
        log_callback_received

        code = request.params["code"]
        params = { redirect_uri: callback_url }.merge(token_params.to_hash(symbolize_keys: true))

        if options.pkce
          verifier = session.delete("omniauth.pkce.verifier")
          params[:code_verifier] = verifier if verifier
        end

        log_token_request(code, params)

        token = client.auth_code.get_token(code, params, deep_symbolize(options.auth_token_params))
        log_token_response_success(token)
        token
      rescue OAuth2::Error => e
        log_token_response_error(e)
        raise
      rescue StandardError => e
        log_token_unexpected_error(e)
        raise
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

      private

      # ── Diagnostic logging ────────────────────────────────────────────────
      # All logs use OmniAuth.logger (writes to STDOUT, captured by `kamal app logs`).
      # Rails.logger writes to a log file inside the container that Docker doesn't capture.
      # Verifier values are one-time-use, so logging them after a failed flow is safe.

      def log_pkce_authorize(generated_verifier, params)
        recomputed_challenge = recompute_challenge(generated_verifier)
        OmniAuth.logger.info({
          event: "pkce.authorize",
          strategy: "slack_openid",
          verifier_full: generated_verifier,
          verifier_length: generated_verifier&.length,
          challenge_full: params[:code_challenge],
          challenge_recomputed: recomputed_challenge,
          challenge_match: params[:code_challenge] == recomputed_challenge,
          challenge_method: params[:code_challenge_method],
          state: session["omniauth.state"],
          state_in_params: params[:state],
          redirect_uri: params[:redirect_uri] || params["redirect_uri"],
          scope_in_params: params[:scope] || params["scope"],
          user_scope_in_params: params[:user_scope] || params["user_scope"],
          response_type: params[:response_type] || params["response_type"],
          client_id_present: client.id.present?,
          client_id_length: client.id&.length,
          session_keys: session.keys
        }.to_json)
      rescue StandardError => e
        OmniAuth.logger.error({ event: "pkce.authorize_log_failed", error: e.message }.to_json)
      end

      def log_callback_received
        OmniAuth.logger.info({
          event: "pkce.callback_received",
          strategy: "slack_openid",
          request_code_present: request.params["code"].present?,
          request_code_value: request.params["code"],
          request_state_present: request.params["state"].present?,
          request_state_value: request.params["state"],
          request_error: request.params["error"],
          request_error_description: request.params["error_description"],
          session_keys: session.keys,
          session_state: session["omniauth.state"],
          session_verifier_present: session["omniauth.pkce.verifier"].present?,
          session_verifier_length: session["omniauth.pkce.verifier"]&.length,
          callback_url: callback_url
        }.to_json)
      rescue StandardError => e
        OmniAuth.logger.error({ event: "pkce.callback_log_failed", error: e.message }.to_json)
      end

      def log_token_request(code, params)
        actual_verifier = params[:code_verifier] || params["code_verifier"]
        recomputed_challenge = recompute_challenge(actual_verifier)
        OmniAuth.logger.info({
          event: "pkce.token_request",
          strategy: "slack_openid",
          code: code,
          code_verifier_full: actual_verifier,
          code_verifier_length: actual_verifier&.length,
          recomputed_challenge_from_verifier: recomputed_challenge,
          all_params: params.transform_keys(&:to_s),
          token_url: client.options[:token_url],
          site: client.options[:site],
          auth_scheme: options[:auth_scheme] || "default(basic_auth)",
          client_id_present: client.id.present?,
          client_secret_present: client.secret.present?
        }.to_json)
      rescue StandardError => e
        OmniAuth.logger.error({ event: "pkce.token_request_log_failed", error: e.message }.to_json)
      end

      def log_token_response_success(token)
        OmniAuth.logger.info({
          event: "pkce.token_response_success",
          strategy: "slack_openid",
          token_present: token.respond_to?(:token) && token.token.present?,
          token_length: (token.token.length if token.respond_to?(:token) && token.token),
          token_class: token.class.name,
          response_params_keys: (token.params.keys.map(&:to_s) if token.respond_to?(:params))
        }.to_json)
      rescue StandardError => e
        OmniAuth.logger.error({ event: "pkce.token_response_success_log_failed", error: e.message }.to_json)
      end

      def log_token_response_error(error)
        response = error.respond_to?(:response) ? error.response : nil
        body = nil
        status = nil
        headers = nil
        parsed_body = nil

        if response
          status  = response.respond_to?(:status) ? response.status : nil
          headers = (response.respond_to?(:headers) ? response.headers.to_hash : nil rescue nil)
          body    = response.respond_to?(:body) ? response.body : response.to_s
          body    = body.to_s
          parsed_body = (JSON.parse(body) rescue nil)
        end

        OmniAuth.logger.error({
          event: "pkce.token_response_error",
          strategy: "slack_openid",
          error_class: error.class.name,
          error_message: error.message,
          error_code: error.respond_to?(:code) ? error.code : nil,
          error_description: error.respond_to?(:description) ? error.description : nil,
          response_status: status,
          response_body_raw: body && body[0, 4000],
          response_body_parsed: parsed_body,
          response_headers: headers,
          backtrace: error.backtrace&.first(15)
        }.to_json)
      rescue StandardError => e
        OmniAuth.logger.error({ event: "pkce.token_response_error_log_failed", error: e.message, original_error: error.message }.to_json)
      end

      def log_token_unexpected_error(error)
        OmniAuth.logger.error({
          event: "pkce.token_unexpected_error",
          strategy: "slack_openid",
          error_class: error.class.name,
          error_message: error.message,
          backtrace: error.backtrace&.first(15)
        }.to_json)
      rescue StandardError
        # nothing — best effort logging
      end

      def recompute_challenge(verifier)
        return nil unless verifier

        Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      end
    end
  end
end

OmniAuth.config.add_camelization "slack_openid", "SlackOpenid"
