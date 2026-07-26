module Integrations
  # The client half of the MCP OAuth story (we already ship the server half
  # on /mcp): discover the remote server's authorization metadata, obtain a
  # client (a pre-registered one when the provider needs it, or dynamic
  # registration when the server supports it), run PKCE, exchange and
  # refresh tokens.
  class OauthClient
    class Error < StandardError; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    class << self
      def begin_flow(server_url:, redirect_uri:, client_id: nil, client_secret: nil)
        metadata = discover(server_url)
        client_id ||= register(metadata, redirect_uri)
        verifier = SecureRandom.urlsafe_base64(48)
        challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        state = SecureRandom.hex(16)

        authorize_url = "#{metadata[:authorization_endpoint]}?" + {
          response_type: "code",
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: state,
          code_challenge: challenge,
          code_challenge_method: "S256",
          resource: server_url,
          scope: metadata[:scope]
        }.compact.to_query

        { authorize_url: authorize_url, state: state, verifier: verifier, client_id: client_id,
          client_secret: client_secret, token_endpoint: metadata[:token_endpoint] }
      end

      def exchange(token_endpoint:, code:, verifier:, client_id:, redirect_uri:, resource:, client_secret: nil)
        token_request(token_endpoint,
                      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                      client_id: client_id, client_secret: client_secret, code_verifier: verifier, resource: resource)
      end

      def refresh(token_endpoint:, refresh_token:, client_id:, resource:, client_secret: nil)
        token_request(token_endpoint,
                      grant_type: "refresh_token", refresh_token: refresh_token,
                      client_id: client_id, client_secret: client_secret, resource: resource)
      end

      # Resource metadata (RFC 9728) names the authorization server; the
      # authorization server metadata (RFC 8414) names the endpoints.
      def discover(server_url)
        server_uri = URI.parse(server_url.to_s)
        raise Error, "invalid MCP server URL" unless server_uri.is_a?(URI::HTTP)

        origin = origin_of(server_uri)
        resource_meta = get_json("#{origin}/.well-known/oauth-protected-resource#{server_uri.path.chomp('/')}") ||
                        get_json("#{origin}/.well-known/oauth-protected-resource")
        authorization_server = Array(resource_meta&.dig("authorization_servers")).first || origin
        scopes = Array(resource_meta&.dig("scopes_supported"))

        auth_meta = authorization_server_metadata(authorization_server)
        raise Error, "the server does not advertise OAuth support" unless auth_meta

        {
          authorization_endpoint: auth_meta.fetch("authorization_endpoint") { raise Error, "no authorization endpoint advertised" },
          token_endpoint: auth_meta.fetch("token_endpoint") { raise Error, "no token endpoint advertised" },
          registration_endpoint: auth_meta["registration_endpoint"],
          scope: scopes.any? ? scopes.join(" ") : nil
        }
      end

      private

      # RFC 8414 places the metadata at the origin with the issuer's path
      # inserted after the well-known segment (GitHub does this); some servers
      # use the simpler issuer-suffix form or OIDC discovery. Try each.
      def authorization_server_metadata(issuer)
        issuer_uri = URI.parse(issuer.to_s)
        origin = origin_of(issuer_uri)
        path = issuer_uri.path.chomp("/")

        get_json("#{origin}/.well-known/oauth-authorization-server#{path}") ||
          get_json("#{issuer.chomp('/')}/.well-known/oauth-authorization-server") ||
          get_json("#{origin}/.well-known/openid-configuration#{path}")
      end

      def origin_of(uri)
        port = uri.port == uri.default_port ? "" : ":#{uri.port}"
        "#{uri.scheme}://#{uri.host}#{port}"
      end

      def register(metadata, redirect_uri)
        endpoint = metadata[:registration_endpoint]
        raise Error, "this provider needs a one-time OAuth app setup. Connect with a token for now" if endpoint.blank?

        response = post_json(endpoint, {
          client_name: "Firefight",
          redirect_uris: [ redirect_uri ],
          grant_types: [ "authorization_code", "refresh_token" ],
          response_types: [ "code" ],
          token_endpoint_auth_method: "none"
        })
        response.fetch("client_id") { raise Error, "client registration returned no client_id" }
      end

      def token_request(token_endpoint, params)
        uri = URI.parse(token_endpoint.to_s)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request.set_form_data(params.compact)
        response = http(uri) { |conn| conn.request(request) }
        body = JSON.parse(response.body.to_s)
        raise Error, body["error_description"] || body["error"] || "token request failed (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        {
          "access_token" => body.fetch("access_token") { raise Error, "no access token returned" },
          "refresh_token" => body["refresh_token"],
          "expires_at" => body["expires_in"] ? (Time.current + body["expires_in"].to_i).iso8601 : nil
        }.compact
      rescue JSON::ParserError
        raise Error, "token endpoint returned invalid JSON"
      end

      def post_json(url, payload)
        uri = URI.parse(url)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Accept"] = "application/json"
        request.body = payload.to_json
        response = http(uri) { |conn| conn.request(request) }
        raise Error, "registration failed (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise Error, "registration endpoint returned invalid JSON"
      end

      def get_json(url)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        response = http(uri) { |conn| conn.request(request) }
        return nil unless response.code.to_i == 200

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end

      def http(uri, &block)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, &block)
      rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
        raise Error, "could not reach the authorization server: #{e.class.name}"
      end
    end
  end
end
