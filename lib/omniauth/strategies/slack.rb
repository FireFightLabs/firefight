require 'omniauth-oauth2'

module OmniAuth
  module Strategies
    class Slack < OmniAuth::Strategies::OAuth2
      option :name, 'slack'

      option :client_options, {
        site: 'https://slack.com',
        authorize_url: 'https://slack.com/oauth/v2/authorize',
        token_url: 'https://slack.com/api/oauth.v2.access'
      }

      # Unique identifier for the user
      uid { raw_info.dig('authed_user', 'id') }

      # Basic info about the user and team
      info do
        {
          name: user_info.dig('user', 'real_name') || user_info.dig('user', 'name'),
          email: user_info.dig('user', 'profile', 'email'),
          image: user_info.dig('user', 'profile', 'image_512'),
          team_id: raw_info.dig('team', 'id'),
          team_name: raw_info.dig('team', 'name')
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
        @team_info ||= raw_info['team'] || {}
      end

      # Detailed user information
      def user_info
        @user_info ||= begin
          user_id = raw_info.dig('authed_user', 'id')
          token = raw_info.dig('authed_user', 'access_token') || access_token.token

          response = access_token.client.request(:get, 'https://slack.com/api/users.info',
            params: { user: user_id },
            headers: { 'Authorization' => "Bearer #{token}" }
          )

          JSON.parse(response.body)
        rescue => e
          Rails.logger.error "Failed to fetch Slack user info: #{e.message}"
          { 'user' => {} }
        end
      end

      # Override callback_url to ensure it's correct
      def callback_url
        full_host + callback_path
      end
    end
  end
end

# Register the strategy with OmniAuth
OmniAuth.config.add_camelization 'slack', 'Slack'
