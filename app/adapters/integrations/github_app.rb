module Integrations
  # GitHub App API access: the install URL customers are sent to, app JWTs,
  # and the server-to-server installation tokens every pack call runs with.
  # Tokens are minted from the installation id captured at connect and cached
  # on the environment row until close to expiry.
  class GithubApp
    class Error < Integrations::Error; end

    API_ROOT = "https://api.github.com".freeze
    PROVIDER_KEY = "github".freeze
    TOKEN_CACHE_KEY = "github_app_token".freeze
    JWT_LIFETIME = 9.minutes
    TOKEN_REFRESH_MARGIN = 5.minutes

    class << self
      def install_url(state:)
        slug = IntegrationProvider.oauth_client(PROVIDER_KEY)[:app_slug]
        return nil if slug.blank?

        "https://github.com/apps/#{slug}/installations/new?" + { state: state }.to_query
      end

      def installation_token(environment_row)
        cached = environment_row.credentials_hash[TOKEN_CACHE_KEY]
        if cached.present?
          expires_at = Time.zone.parse(cached["expires_at"].to_s)
          return cached["token"] if expires_at && expires_at > TOKEN_REFRESH_MARGIN.from_now
        end

        mint_token(environment_row)
      end

      def get(path, token:)
        uri = URI.parse("#{API_ROOT}#{path}")
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}"
        apply_api_headers(request)
        parse_response(Http.request(uri, request, error_class: Error))
      end

      private

      def mint_token(environment_row)
        installation_id = environment_row.base_config["installation_id"].to_s
        if installation_id.blank?
          raise Error, "No GitHub App installation is linked to this connection. Reconnect GitHub to link one."
        end

        uri = URI.parse("#{API_ROOT}/app/installations/#{installation_id}/access_tokens")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{app_jwt}"
        apply_api_headers(request)
        body = parse_response(Http.request(uri, request, error_class: Error))

        token = body.fetch("token") { raise Error, "GitHub returned no installation token" }
        environment_row.store_credential!(TOKEN_CACHE_KEY, "token" => token, "expires_at" => body["expires_at"])
        token
      end

      # GitHub accepts the App's client id as the JWT issuer, so the same
      # INTEGRATION_GITHUB_CLIENT_ID that serves OAuth serves signing. Only
      # the private key is extra.
      def app_jwt
        oauth = IntegrationProvider.oauth_client(PROVIDER_KEY)
        if oauth[:client_id].blank? || oauth[:private_key].blank?
          raise Error, "GitHub App credentials are not configured on this install."
        end

        now = Time.current.to_i
        key = OpenSSL::PKey::RSA.new(oauth[:private_key].gsub('\n', "\n"))
        JWT.encode({ iat: now - 60, exp: now + JWT_LIFETIME.to_i, iss: oauth[:client_id] }, key, "RS256")
      rescue OpenSSL::PKey::RSAError
        raise Error, "The configured GitHub App private key is not a valid RSA key."
      end

      def apply_api_headers(request)
        request["Accept"] = "application/vnd.github+json"
        request["X-GitHub-Api-Version"] = "2022-11-28"
      end

      def parse_response(response)
        body = JSON.parse(response.body.to_s)
        unless response.code.to_i.between?(200, 299)
          raise Error, "GitHub: #{body['message'] || "HTTP #{response.code}"}"
        end

        body
      rescue JSON::ParserError
        raise Error, "GitHub returned invalid JSON (HTTP #{response.code})"
      end
    end
  end
end
