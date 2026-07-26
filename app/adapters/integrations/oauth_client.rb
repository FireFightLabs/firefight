module Integrations
  # The client half of the MCP OAuth story (we already ship the server half
  # on /mcp): discover the remote server's authorization metadata, register
  # Firefight via dynamic client registration, run PKCE, exchange and
  # refresh tokens. One flow for every OAuth-capable MCP server, no
  # per-provider code.
  class OauthClient
    class Error < StandardError; end

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    class << self
      def begin_flow(server_url:, redirect_uri:)
        metadata = discover(server_url)
        client_id = register(metadata, redirect_uri)
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
          resource: server_url
        }.to_query

        { authorize_url: authorize_url, state: state, verifier: verifier,
          client_id: client_id, token_endpoint: metadata[:token_endpoint] }
      end

      def exchange(token_endpoint:, code:, verifier:, client_id:, redirect_uri:, resource:)
        token_request(token_endpoint,
                      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                      client_id: client_id, code_verifier: verifier, resource: resource)
      end

      def refresh(token_endpoint:, refresh_token:, client_id:, resource:)
        token_request(token_endpoint,
                      grant_type: "refresh_token", refresh_token: refresh_token,
                      client_id: client_id, resource: resource)
      end

      # Resource metadata (RFC 9728) names the authorization server; the
      # authorization server metadata (RFC 8414) names the endpoints.
      def discover(server_url)
        server_uri = URI.parse(server_url.to_s)
        raise Error, "invalid MCP server URL" unless server_uri.is_a?(URI::HTTP)

        origin = "#{server_uri.scheme}://#{server_uri.host}#{server_uri.port == server_uri.default_port ? '' : ":#{server_uri.port}"}"
        resource_meta = get_json("#{origin}/.well-known/oauth-protected-resource#{server_uri.path.chomp('/')}") ||
                        get_json("#{origin}/.well-known/oauth-protected-resource")
        authorization_server = Array(resource_meta&.dig("authorization_servers")).first || origin

        auth_meta = get_json("#{authorization_server.chomp('/')}/.well-known/oauth-authorization-server")
        raise Error, "the server does not advertise OAuth support" unless auth_meta

        {
          authorization_endpoint: auth_meta.fetch("authorization_endpoint") { raise Error, "no authorization endpoint advertised" },
          token_endpoint: auth_meta.fetch("token_endpoint") { raise Error, "no token endpoint advertised" },
          registration_endpoint: auth_meta["registration_endpoint"]
        }
      end

      private

      def register(metadata, redirect_uri)
        endpoint = metadata[:registration_endpoint]
        raise Error, "the server does not support automatic client registration; connect with a token instead" if endpoint.blank?

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
        request.set_form_data(params)
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
