module Integrations
  # OAuth client for remote MCP servers. Uses a pre-registered client when the
  # provider needs one, dynamic registration otherwise.
  class OauthClient
    class Error < Integrations::Error; end
    # The authorization server refused a refresh token as no longer good (RFC 6749 section 5.2, invalid_grant), such as one
    # past the time a provider keeps a sign-in for, so only signing in again reaches the server.
    class SignInEnded < Error; end
    # A token endpoint's refusal with the error code it gave.
    class Refused < Error
      attr_reader :code

      def initialize(message, code: nil)
        @code = code
        super(message)
      end
    end

    INVALID_GRANT = "invalid_grant".freeze

    REFRESH_MARGIN = 60.seconds

    class << self
      # Install-first providers such as GitHub never reach this client. endpoints holds the authorization_endpoint and
      # token_endpoint a provider's region names, used over the ones its server's metadata gives.
      # scopes narrows what is asked for to those of the server's scopes, for a provider whose scopes include changes it
      # should not be asked for.
      def begin_flow(server_url:, redirect_uri:, client_id: nil, endpoints: {}, scopes: [])
        metadata = discover(server_url, endpoints, scopes)
        client_id ||= register(metadata, redirect_uri)
        state = SecureRandom.hex(16)

        verifier = SecureRandom.urlsafe_base64(48)
        challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        authorize_url = with_query(metadata[:authorization_endpoint], {
          response_type: "code",
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: state,
          code_challenge: challenge,
          code_challenge_method: "S256",
          resource: resource_of(server_url),
          scope: metadata[:scope]
        }.compact)

        { authorize_url: authorize_url, state: state, verifier: verifier, client_id: client_id,
          token_endpoint: metadata[:token_endpoint] }
      end

      # A provider's own OAuth application, whose endpoints are known rather than discovered, for a native connection.
      # A code challenge goes along only where the provider takes one.
      def begin_app_flow(authorization_endpoint:, token_endpoint:, client_id:, scope:, redirect_uri:, params: {}, pkce: false)
        state = SecureRandom.hex(16)
        verifier = SecureRandom.urlsafe_base64(48) if pkce
        challenge = verifier && Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        query = { response_type: "code", client_id: client_id, redirect_uri: redirect_uri, state: state, scope: scope,
                  code_challenge: challenge, code_challenge_method: ("S256" if challenge) }.merge(params.to_h.symbolize_keys).compact
        { authorize_url: with_query(authorization_endpoint, query), state: state, verifier: verifier, client_id: client_id,
          token_endpoint: token_endpoint }
      end

      # The credential shape is private to this class. Callers persist it
      # verbatim and never index into it.
      # json sends the token request as JSON, for a provider whose token endpoint documents only that.
      def exchange(token_endpoint:, code:, verifier:, client_id:, redirect_uri:, resource:, client_secret: nil, json: false)
        token = token_request(token_endpoint,
                              { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri,
                                client_id: client_id, client_secret: client_secret,
                                code_verifier: verifier, resource: resource && resource_of(resource) },
                              json: json)
        token.merge(
          "token_endpoint" => token_endpoint, "client_id" => client_id,
          "client_secret" => client_secret, "resource" => resource && resource_of(resource), "token_format" => ("json" if json)
        ).compact
      end

      # Raises SignInEnded when the server no longer takes the refresh token.
      def refresh(credentials)
        rotated = token_request(credentials["token_endpoint"],
                                { grant_type: "refresh_token", refresh_token: credentials["refresh_token"],
                                  client_id: credentials["client_id"], client_secret: credentials["client_secret"],
                                  resource: credentials["resource"] },
                                json: credentials["token_format"] == "json")
        credentials.merge(rotated) { |_key, previous, current| current.presence || previous }
      rescue Refused => error
        raise SignInEnded, error.message if error.code == INVALID_GRANT

        raise
      end

      def access_token(credentials)
        credentials["access_token"]
      end

      def stale?(credentials)
        return false if credentials["refresh_token"].blank?

        expires_at = credentials["expires_at"].presence && Time.zone.parse(credentials["expires_at"])
        expires_at.present? && expires_at <= REFRESH_MARGIN.from_now
      end

      # The server a token is for, without a query that only picks how the server answers, such as one asking it to
      # list every tool on its own. RFC 9728 names the resource by its address alone.
      def resource_of(server_url)
        uri = URI.parse(server_url.to_s)
        return server_url unless uri.is_a?(URI::HTTP) && (uri.query || uri.fragment)

        uri.query = nil
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        server_url
      end

      # RFC 9728 resource metadata names the authorization server, RFC 8414 server metadata names the endpoints.
      # endpoints, from a provider's region, stand in for the ones the metadata gives, and are enough without it.
      # scopes, when given, are asked for in place of every scope the server lists, and each must be one it lists. A server
      # that lists none is asked for none, since a scope it never named cannot be known to narrow anything.
      def discover(server_url, endpoints = {}, scopes = [])
        server_uri = URI.parse(server_url.to_s)
        raise Error, "invalid MCP server URL" unless server_uri.is_a?(URI::HTTP)

        origin = origin_of(server_uri)
        resource_meta = get_json("#{origin}/.well-known/oauth-protected-resource#{server_uri.path.chomp('/')}") ||
                        get_json("#{origin}/.well-known/oauth-protected-resource")
        authorization_server = Array(resource_meta&.dig("authorization_servers")).first || origin
        supported = Array(resource_meta&.dig("scopes_supported"))
        missing = Array(scopes) - supported
        raise Error, "the server no longer offers #{missing.join(', ')}" if supported.any? && missing.any?

        scopes = Array(scopes).any? && supported.any? ? Array(scopes) : supported

        auth_meta = authorization_server_metadata(authorization_server).to_h.merge(endpoints.to_h.transform_keys(&:to_s))
        raise Error, "the server does not advertise OAuth support" if auth_meta.empty?

        {
          authorization_endpoint: auth_meta.fetch("authorization_endpoint") { raise Error, "no authorization endpoint advertised" },
          token_endpoint: auth_meta.fetch("token_endpoint") { raise Error, "no token endpoint advertised" },
          registration_endpoint: auth_meta["registration_endpoint"],
          scope: scopes.any? ? scopes.join(" ") : nil
        }
      end

      private

      # Servers differ on where the metadata lives (RFC 8414 path insertion as
      # GitHub does, issuer suffix, or OIDC discovery), so try each.
      def authorization_server_metadata(issuer)
        issuer_uri = URI.parse(issuer.to_s)
        origin = origin_of(issuer_uri)
        path = issuer_uri.path.chomp("/")

        get_json("#{origin}/.well-known/oauth-authorization-server#{path}") ||
          get_json("#{issuer.chomp('/')}/.well-known/oauth-authorization-server") ||
          get_json("#{origin}/.well-known/openid-configuration#{path}")
      end

      # An authorization endpoint may carry a query of its own, such as the account it signs in to, which is kept.
      def with_query(endpoint, params)
        uri = URI.parse(endpoint.to_s)
        uri.query = [ uri.query.presence, params.to_query ].compact.join("&")
        uri.to_s
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

      def token_request(token_endpoint, params, json: false)
        uri = URI.parse(token_endpoint.to_s)
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        if json
          request["Content-Type"] = "application/json"
          request.body = params.compact.to_json
        else
          request.set_form_data(params.compact)
        end
        response = Http.request(uri, request, error_class: Error)
        body = JSON.parse(response.body.to_s)
        unless response.code.to_i.between?(200, 299)
          raise Refused.new(body["error_description"].presence || body["error"].presence || "token request failed (HTTP #{response.code})", code: body["error"])
        end

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
        response = Http.request(uri, request, error_class: Error)
        raise Error, "registration failed (HTTP #{response.code})" unless response.code.to_i.between?(200, 299)

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        raise Error, "registration endpoint returned invalid JSON"
      end

      def get_json(url)
        uri = URI.parse(url)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        response = Http.request(uri, request, error_class: Error)
        return nil unless response.code.to_i == 200

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
