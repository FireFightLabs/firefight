require "omniauth-oauth2"

module OmniAuth
  module Strategies
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

      def authorize_params
        super.merge(scope: "", user_scope: "openid,profile,email")
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
          user_token = access_token.params.dig("authed_user", "access_token")
          response = access_token.client.request(
            :get,
            "https://slack.com/api/openid.connect.userInfo",
            headers: { "Authorization" => "Bearer #{user_token}" }
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
