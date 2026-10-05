module Integrations
  # Installation tokens are minted from the installation id captured at
  # connect and cached on the environment row until close to expiry.
  class GithubApp
    class Error < Integrations::Error; end
    # Out of API calls for now, so whatever reads in bulk stops rather than failing every call that follows.
    class RateLimited < Error
      include Integrations::RateLimited
    end

    API_ROOT = "https://api.github.com".freeze
    PROVIDER_KEY = "github".freeze
    TOKEN_CACHE_KEY = "github_app_token".freeze
    JWT_LIFETIME = 9.minutes
    TOKEN_REFRESH_MARGIN = 5.minutes
    # A deployment gathers a handful of statuses (queued, in progress, success, inactive), so this reads all of them.
    DEPLOYMENT_STATUS_LIMIT = 20
    DOWNLOAD_LIMIT = 2_000_000

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

      def post(path, body, token:)
        uri = URI.parse("#{API_ROOT}#{path}")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        apply_api_headers(request)
        request.body = body.to_json
        parse_response(Http.request(uri, request, error_class: Error))
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
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token}"
        apply_api_headers(request)
        response = Http.request(uri, request, error_class: Error)
        parse_response(response) unless response.is_a?(Net::HTTPRedirection)

        Http.download(response["location"], provider_key: PROVIDER_KEY, error_class: Error, limit: limit)
      end

      # Blame at a given commit exists only in GitHub's GraphQL API.
      def graphql(query, variables, token:)
        uri = URI.parse("#{API_ROOT}/graphql")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        apply_api_headers(request)
        request.body = { query: query, variables: variables }.to_json
        body = parse_response(Http.request(uri, request, error_class: Error))
        raise Error, "GitHub: #{body['errors'].filter_map { |error| Sentence.clean(error['message']) }.join(', ')}" if body["errors"].present?

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

      def mint_token(environment_row)
        installation_id = ConnectionSettings.of(environment_row).installation_id.to_s
        if installation_id.blank?
          raise Error, "No GitHub App installation is linked to this connection. Reconnect GitHub to link one."
        end

        uri = URI.parse("#{API_ROOT}/app/installations/#{installation_id}/access_tokens")
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{app_jwt}"
        apply_api_headers(request)
        body = parse_response(Http.request(uri, request, error_class: Error))

        token = body.fetch("token") { raise Error, "GitHub returned no installation token" }
        ConnectionSettings.of(environment_row).store_credential!(TOKEN_CACHE_KEY, "token" => token, "expires_at" => body["expires_at"])
        token
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

          raise Error, message
        end

        body
      rescue JSON::ParserError
        raise Error, "GitHub returned invalid JSON (HTTP #{response.code})"
      end
    end
  end
end
