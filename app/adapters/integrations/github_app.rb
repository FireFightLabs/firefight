module Integrations
  # Installation tokens are minted from the installation id captured at
  # connect and cached on the environment row until close to expiry.
  class GithubApp
    class Error < Integrations::Error; end
    # Out of API calls for now, so whatever reads in bulk stops rather than failing every call that follows.
    class RateLimited < Error
      include Integrations::RateLimited
    end
    # The installation was not granted a permission the call needs, which GitHub says as "Resource not accessible by
    # integration" (docs.github.com, REST API, troubleshooting).
    class NotPermitted < Error; end
    # GitHub did not accept the token, such as one minted for an installation that changed since.
    class Unauthorized < Error; end
    # GitHub answered that the repository is not there, or not one the installation can see, the one answer a re-read
    # takes as gone.
    class NotFound < Error; end

    API_ROOT = "https://api.github.com".freeze
    PROVIDER_KEY = "github".freeze
    TOKEN_CACHE_KEY = "github_app_token".freeze
    JWT_LIFETIME = 9.minutes
    TOKEN_REFRESH_MARGIN = 5.minutes
    # A deployment gathers a handful of statuses (queued, in progress, success, inactive), so this reads all of them.
    DEPLOYMENT_STATUS_LIMIT = 20
    DOWNLOAD_LIMIT = 2_000_000
    PROVIDER = "GitHub".freeze
    NOT_PERMITTED = /not accessible by integration/i
    NOT_FOUND = 404
    UNAUTHORIZED = 401
    REFINE = ->(code, said) { (NotPermitted if code == 403 && said.match?(NOT_PERMITTED)) || (Unauthorized if code == UNAUTHORIZED) }

    # An installation token with the connection it was minted for. GitHub fixes a token's permissions when it is minted
    # (docs.github.com, Generating an installation access token for a GitHub App), so once an owner accepts new
    # permissions a token minted before still lacks them, and GitHub refuses it as "Resource not accessible by
    # integration". A call refused that way, or with a 401, mints a fresh token and is tried once more (refresh!). A
    # token minted for this call is never minted again, so a permission the installation truly lacks fails once.
    class InstallationToken
      def initialize(environment_row, value, fresh:)
        @row = environment_row
        @value = value
        @fresh = fresh
      end

      def to_s = @value

      def to_str = @value

      def inspect = "#<#{self.class.name} [redacted]>"

      def ==(other) = other.respond_to?(:to_str) && @value == other.to_str

      # Whether there is a new token to try.
      def refresh!
        return false if @fresh

        @fresh = true
        @value = GithubApp.mint_token(@row)
        true
      end
    end

    BLAME_QUERY = <<~GRAPHQL.freeze
      query($owner: String!, $name: String!, $expression: String!, $path: String!) {
        repository(owner: $owner, name: $name) {
          object(expression: $expression) {
            ... on Commit {
              blame(path: $path) {
                ranges {
                  startingLine
                  endingLine
                  commit {
                    oid
                    committedDate
                    messageHeadline
                    author { name user { login } }
                    associatedPullRequests(first: 1) { nodes { number title } }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    class << self
      def install_url(state:)
        slug = IntegrationProvider.oauth_client(PROVIDER_KEY)[:app_slug]
        return nil if slug.blank?

        "https://github.com/apps/#{slug}/installations/new?" + { state: state }.to_query
      end

      def installation_token(environment_row)
        cached = ConnectionSettings.of(environment_row).credential(TOKEN_CACHE_KEY).to_h
        if cached.present?
          expires_at = Time.zone.parse(cached["expires_at"].to_s)
          return InstallationToken.new(environment_row, cached["token"], fresh: false) if expires_at && expires_at > TOKEN_REFRESH_MARGIN.from_now
        end

        InstallationToken.new(environment_row, mint_token(environment_row), fresh: true)
      end

      # Mints a token for the installation and caches it on the row, with the permissions GitHub says it holds.
      def mint_token(environment_row)
        uri = URI.parse("#{API_ROOT}/app/installations/#{installation_id!(environment_row)}/access_tokens")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{app_jwt}"
        apply_api_headers(request)
        body = parse_response(Http.request(uri, request, error_class: Error))

        token = body.fetch("token") { raise Error, "GitHub returned no installation token" }
        settings = ConnectionSettings.of(environment_row)
        settings.store_credential!(TOKEN_CACHE_KEY, "token" => token, "expires_at" => body["expires_at"])
        settings.store_installation_access!(body["permissions"]) if body["permissions"].is_a?(Hash)
        token
      end

      # Drops the cached token, so the next call mints one holding what the installation was granted now.
      def forget_token!(environment_row)
        settings = ConnectionSettings.of(environment_row)
        settings.forget_credential!(TOKEN_CACHE_KEY) if settings.credential(TOKEN_CACHE_KEY)
      end

      # The installation as GitHub has it now, read with the App's own JWT (docs.github.com, REST API, Get an installation
      # for the authenticated app): its account, its settings page, its permissions and whether it is suspended. GitHub
      # answers 404 for one that was deleted. Answers the body, or nil for one that is gone.
      def installation(environment_row)
        get("/app/installations/#{installation_id!(environment_row)}", token: app_jwt)
      rescue NotFound
        nil
      end

      # Removes the App from the account it is installed on (docs.github.com, REST API, Delete an installation for the
      # authenticated app), which GitHub answers 204. One already gone counts as removed.
      def uninstall(environment_row)
        uri = URI.parse("#{API_ROOT}/app/installations/#{installation_id!(environment_row)}")
        request = Net::HTTP::Delete.new(uri)
        request["Authorization"] = "Bearer #{app_jwt}"
        apply_api_headers(request)
        response = Http.request(uri, request, error_class: Error)
        return true if response.code.to_i == 204 || response.code.to_i == NOT_FOUND

        parse_response(response)
        true
      end

      def get(path, token:)
        uri = URI.parse("#{API_ROOT}#{path}")
        refreshing(token) do |value|
          request = Net::HTTP::Get.new(uri)
          request["Authorization"] = "Bearer #{value}"
          apply_api_headers(request)
          parse_response(Http.request(uri, request, error_class: Error))
        end
      end

      def post(path, body, token:)
        uri = URI.parse("#{API_ROOT}#{path}")
        refreshing(token) do |value|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{value}"
          request["Content-Type"] = "application/json"
          apply_api_headers(request)
          request.body = body.to_json
          parse_response(Http.request(uri, request, error_class: Error))
        end
      end

      # A change that answers 201, 202 or 204, often with no body, such as rerunning or canceling a workflow run. Read with
      # Http.json, so an empty answer counts as done and reads as {}, and a missing permission raises NotPermitted.
      def act(path, body = nil, token:)
        uri = URI.parse("#{API_ROOT}#{path}")
        refreshing(token) do |value|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{value}"
          apply_api_headers(request)
          unless body.nil?
            request["Content-Type"] = "application/json"
            request.body = body.to_json
          end
          Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: REFINE, rate_limited: RateLimited)
        end
      end

      # One commit on a new branch, holding every changed file, and a pull request for it into base, ready for review.
      # The commit's parent is base_sha, the commit the change was written against, so the pull request never undoes
      # what reached base since. files maps a path to its new content as base64 with its mode, or to nil when the change
      # deletes it. Returns the pull request as GitHub gives it.
      def open_pull_request(repo, base:, base_sha:, branch:, title:, body:, message:, files:, token:)
        head = base_sha
        base_tree = get("/repos/#{repo}/git/commits/#{head}", token: token).dig("tree", "sha")
        entries = files.map do |path, file|
          next { path: path, mode: "100644", type: "blob", sha: nil } if file.nil?

          blob = post("/repos/#{repo}/git/blobs", { content: file[:content], encoding: "base64" }, token: token)
          { path: path, mode: file[:mode], type: "blob", sha: blob["sha"] }
        end
        tree = post("/repos/#{repo}/git/trees", { base_tree: base_tree, tree: entries }, token: token)
        commit = post("/repos/#{repo}/git/commits", { message: message, tree: tree["sha"], parents: [ head ] }, token: token)
        post("/repos/#{repo}/git/refs", { ref: "refs/heads/#{branch}", sha: commit["sha"] }, token: token)
        post("/repos/#{repo}/pulls", { title: title, head: branch, base: base, body: body, draft: false }, token: token)
      end

      # A file GitHub answers with a redirect to a short-lived signed address, such as a job's log. The address is fetched
      # without the token, on a public host only, and the text is cut to its last limit bytes, where a job says why it failed.
      def download(path, token:, limit: DOWNLOAD_LIMIT)
        uri = URI.parse("#{API_ROOT}#{path}")
        response = refreshing(token) do |value|
          request = Net::HTTP::Get.new(uri)
          request["Authorization"] = "Bearer #{value}"
          apply_api_headers(request)
          Http.request(uri, request, error_class: Error).tap { |answer| parse_response(answer) unless answer.is_a?(Net::HTTPRedirection) }
        end

        Http.download(response["location"], provider_key: PROVIDER_KEY, error_class: Error, limit: limit)
      end

      # Blame at a given commit exists only in GitHub's GraphQL API.
      # A missing permission is said in the errors of a 200 answer, with the same words as the REST API's 403.
      def graphql(query, variables, token:)
        uri = URI.parse("#{API_ROOT}/graphql")
        body = refreshing(token) do |value|
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{value}"
          request["Content-Type"] = "application/json"
          apply_api_headers(request)
          request.body = { query: query, variables: variables }.to_json
          answer = parse_response(Http.request(uri, request, error_class: Error))
          said = Array(answer["errors"]).filter_map { |error| Sentence.clean(error["message"]) }
          raise (said.any? { |message| message.match?(NOT_PERMITTED) } ? NotPermitted : Error), "GitHub: #{said.join(', ')}" if answer["errors"].present?

          answer
        end
        body.fetch("data")
      end

      # When a deployment succeeded, or nil. GitHub marks an older deployment inactive once a newer one goes out, so its
      # latest status is no longer success. Any success among its statuses counts, timed when that status was written.
      def deployment_succeeded_at(repo, deployment_id, token:)
        statuses = Array(get("/repos/#{repo}/deployments/#{deployment_id}/statuses?per_page=#{DEPLOYMENT_STATUS_LIMIT}", token: token))
        success = statuses.find { |status| status["state"] == "success" }
        success && Time.zone.parse(success["created_at"].to_s)
      end

      # Who last changed each range of a file as it stood at a commit, branch or tag.
      def blame(repo, path, expression, token:)
        owner, name = repo.split("/", 2)
        data = graphql(BLAME_QUERY, { owner: owner, name: name, expression: expression, path: path }, token: token)
        Array(data.dig("repository", "object", "blame", "ranges"))
      end

      private

      # Runs the call with the token, and once more with a fresh one when GitHub refused a token minted before the
      # installation changed (InstallationToken#refresh!). A plain string, such as the App's own JWT, is never refreshed.
      def refreshing(token)
        yield token.to_s
      rescue NotPermitted, Unauthorized
        raise unless token.respond_to?(:refresh!) && token.refresh!

        yield token.to_s
      end

      def installation_id!(environment_row)
        installation_id = ConnectionSettings.of(environment_row).installation_id.to_s
        raise Error, "No GitHub App installation is linked to this connection. Reconnect GitHub to link one." if installation_id.blank?

        installation_id
      end

      # GitHub accepts the App's client id as the JWT issuer, so the OAuth
      # client id serves signing too.
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

      def rate_limited?(response)
        response.code.to_i == 429 || (response.code.to_i == 403 && (response["x-ratelimit-remaining"] == "0" || response["retry-after"].present?))
      end

      def parse_response(response)
        body = JSON.parse(response.body.to_s)
        unless response.code.to_i.between?(200, 299)
          message = "GitHub: #{body['message'] || "HTTP #{response.code}"}"
          raise RateLimited, message if rate_limited?(response)
          raise NotFound, message if response.code.to_i == NOT_FOUND
          raise Unauthorized, message if response.code.to_i == UNAUTHORIZED
          raise NotPermitted, message if response.code.to_i == 403 && message.match?(NOT_PERMITTED)

          raise Error, message
        end

        body
      rescue JSON::ParserError
        raise Error, "GitHub returned invalid JSON (HTTP #{response.code})"
      end
    end
  end
end
