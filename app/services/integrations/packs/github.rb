module Integrations
  module Packs
    # File reads, search and blame run against a local clone through git object commands only,
    # so repo content never touches the filesystem API.
    class Github < NativePack
      REPO_FORMAT = /\A[\w.\-]+\/[\w.\-]+\z/
      PATH_FORMAT = /\A[^\/\0][^\0]*\z/
      # Refused in the executor, not the prompt. Prompts can be talked around.
      SENSITIVE_PATHS = /\.env|credential|secret|\.pem\z|\.key\z|id_rsa|id_ed25519|\.p12\z|\.pfx\z/i
      FILE_LIMIT = 30
      LINE_LIMIT = 200
      MATCH_LIMIT = 50
      CONTEXT_LINES = 10
      # Each deployment needs a second call for its state.
      DEPLOYMENT_LIMIT = 3
      MERGED_LIMIT = 10
      # Closed pull requests include unmerged ones, so fetch more than we keep.
      CLOSED_CANDIDATES = 50

      tool :pr_lookup,
           description: "Fetch a pull request: title, state, author, merge status, and changed files",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "number" => { "type" => "integer", "description" => "Pull request number" }
             },
             "required" => [ "repo", "number" ]
           },
           read_only: true

      tool :commit_lookup,
           description: "Fetch a commit: message, author, stats, and changed files",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "sha" => { "type" => "string", "description" => "Commit SHA" }
             },
             "required" => [ "repo", "sha" ]
           },
           read_only: true

      tool :recent_deployments,
           description: "List recent deployments for a repository, newest first, each with the ref deployed, the environment and the outcome",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "deployment_environment" => { "type" => "string", "description" => "Limit to one deployment environment, e.g. production (optional)" }
             },
             "required" => [ "repo" ]
           },
           read_only: true

      tool :merged_pull_requests,
           description: "List pull requests merged into a repository, newest first, optionally only those merged since a given time",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "since" => { "type" => "string", "description" => "Only pull requests merged at or after this time, as ISO 8601 (optional)" }
             },
             "required" => [ "repo" ]
           },
           read_only: true

      tool :fetch_file,
           description: "Read a file from the repository, optionally sliced to a line range with surrounding context",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "path" => { "type" => "string", "description" => "File path within the repository" },
               "start_line" => { "type" => "integer", "description" => "First line of interest (optional; the slice includes context around it)" },
               "end_line" => { "type" => "integer", "description" => "Last line of interest (optional)" }
             },
             "required" => [ "repo", "path" ]
           },
           read_only: true

      tool :code_search,
           description: "Regex search across the repository's current code, returning path:line references with a matching snippet",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "pattern" => { "type" => "string", "description" => "Extended regex to search for, e.g. def assign_clinician|AssignmentService" },
               "path_prefix" => { "type" => "string", "description" => "Limit the search to paths under this prefix (optional)" }
             },
             "required" => [ "repo", "pattern" ]
           },
           read_only: true

      tool :blame,
           description: "Attribute a line range to the commits that last touched it - the step that finds the culprit change",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "path" => { "type" => "string", "description" => "File path within the repository" },
               "start_line" => { "type" => "integer", "description" => "First line of the range" },
               "end_line" => { "type" => "integer", "description" => "Last line of the range" }
             },
             "required" => [ "repo", "path", "start_line", "end_line" ]
           },
           read_only: true

      def self.install_url(state:)
        GithubApp.install_url(state: state)
      end

      def pr_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        number = Integer(arguments["number"].to_s, exception: false)
        fail! "number must be an integer" unless number

        token = GithubApp.installation_token(environment_row)
        pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
        files = GithubApp.get("/repos/#{repo}/pulls/#{number}/files?per_page=#{FILE_LIMIT}", token: token)

        <<~TEXT
          PR ##{pull['number']}: #{pull['title']}
          State: #{pull['merged_at'] ? "merged at #{pull['merged_at']}" : pull['state']}
          Author: #{pull.dig('user', 'login')}
          Branch: #{pull.dig('head', 'ref')} -> #{pull.dig('base', 'ref')}
          Changes: #{pull['changed_files']} files, +#{pull['additions']} -#{pull['deletions']}

          #{file_lines(files, pull['changed_files'])}
          #{pull['body'].presence || '(no description)'}
        TEXT
      end

      def commit_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        sha = arguments["sha"].to_s
        fail! "sha must be a commit SHA" unless sha.match?(/\A\h{6,40}\z/)

        token = GithubApp.installation_token(environment_row)
        commit = GithubApp.get("/repos/#{repo}/commits/#{sha}", token: token)

        <<~TEXT
          Commit #{commit['sha']}
          Author: #{commit.dig('commit', 'author', 'name')} at #{commit.dig('commit', 'author', 'date')}
          Changes: +#{commit.dig('stats', 'additions')} -#{commit.dig('stats', 'deletions')}

          #{commit.dig('commit', 'message')}

          #{file_lines(commit['files'], commit['files']&.size)}
        TEXT
      end

      def recent_deployments(environment_row:, arguments:)
        repo = repo_argument(arguments)
        token = GithubApp.installation_token(environment_row)
        deployments = GithubApp.get("/repos/#{repo}/deployments?#{deployment_query(arguments)}", token: token)
        return "No deployments recorded for #{repo}." if deployments.blank?

        Array(deployments).map { |deployment| deployment_line(repo, deployment, token) }.join("\n")
      end

      def merged_pull_requests(environment_row:, arguments:)
        repo = repo_argument(arguments)
        since = since_argument(arguments)
        token = GithubApp.installation_token(environment_row)
        closed = GithubApp.get(
          "/repos/#{repo}/pulls?state=closed&sort=updated&direction=desc&per_page=#{CLOSED_CANDIDATES}",
          token: token
        )

        merged = Array(closed).select { |pull| merged_since?(pull, since) }.first(MERGED_LIMIT)
        return "No pull requests merged#{since ? " since #{since.iso8601}" : ''} in #{repo}." if merged.empty?

        merged.map { |pull| merged_line(pull) }.join("\n")
      end

      def fetch_file(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)

        CloneManager.with_repo(environment_row: environment_row, repo: repo) do |dir|
          lines = read_file_lines(dir, path)
          from, to = slice_range(arguments, lines.size)

          numbered = lines[(from - 1)..(to - 1)].each_with_index.map do |line, index|
            format("%4d  %s", from + index, line.chomp)
          end
          "#{path}:#{from}-#{to} (of #{lines.size} lines)\n#{numbered.join("\n")}"
        end
      end

      def code_search(environment_row:, arguments:)
        repo = repo_argument(arguments)
        pattern = arguments["pattern"].to_s
        fail! "pattern is required" if pattern.blank?

        CloneManager.with_repo(environment_row: environment_row, repo: repo) do |dir|
          hits = CloneManager.grep(dir, pattern, arguments["path_prefix"].presence)
                             .reject { |line| line.split(":", 2).first.to_s.match?(SENSITIVE_PATHS) }
          shown = hits.first(MATCH_LIMIT).map { |line| line.truncate(200) }
          return "No matches." if shown.empty?

          result = shown.join("\n")
          result += "\n... #{hits.size - shown.size} more matches. Refine the pattern." if hits.size > shown.size
          result
        end
      end

      def blame(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        from = Integer(arguments["start_line"].to_s, exception: false)
        to = Integer(arguments["end_line"].to_s, exception: false)
        fail! "start_line and end_line must be integers" unless from && to
        fail! "line range must be ascending and at most #{LINE_LIMIT} lines" unless from <= to && (to - from) < LINE_LIMIT

        CloneManager.with_repo(environment_row: environment_row, repo: repo) do |dir|
          format_blame(CloneManager.blame(dir, path, from, to))
        end
      end

      def check_health!(environment_row)
        GithubApp.installation_token(environment_row)
      end

      private

      # ConnectionToolFactory strips "environment" from arguments before a pack sees it.
      def deployment_query(arguments)
        query = { "per_page" => DEPLOYMENT_LIMIT }
        target = arguments["deployment_environment"].to_s
        query["environment"] = target if target.present?
        query.to_query
      end

      def deployment_line(repo, deployment, token)
        state = deployment_state(repo, deployment["id"], token)
        ref = deployment["ref"].presence || deployment["sha"].to_s[0, 8]
        target = deployment["environment"].presence || "unknown environment"
        creator = deployment.dig("creator", "login").presence || "unknown"

        "#{deployment['created_at']}  #{target}  #{ref}  #{state}  by #{creator}"
      end

      # A deployment has no state field. Its newest status row is the outcome.
      def deployment_state(repo, deployment_id, token)
        statuses = GithubApp.get("/repos/#{repo}/deployments/#{deployment_id}/statuses?per_page=1", token: token)
        Array(statuses).first&.fetch("state", nil).presence || "no status"
      rescue GithubApp::Error
        "state unavailable"
      end

      # Time.zone.parse accepts "last tuesday" and would filter on a window the caller never gave.
      def since_argument(arguments)
        raw = arguments["since"].to_s
        return nil if raw.blank?

        Time.iso8601(raw)
      rescue ArgumentError
        fail! "since must be an ISO 8601 time, for example 2026-09-12T09:00:00Z"
      end

      def merged_since?(pull, since)
        merged_at = pull["merged_at"]
        return false if merged_at.blank?
        return true if since.nil?

        Time.zone.parse(merged_at) >= since
      end

      def merged_line(pull)
        "PR ##{pull['number']}  #{pull['title']}  merged #{pull['merged_at']} " \
          "by #{pull.dig('user', 'login')} into #{pull.dig('base', 'ref')}"
      end

      def read_file_lines(dir, path)
        CloneManager.show_file(dir, path).lines
      rescue CloneManager::Error
        fail! "No file at '#{path}' on the default branch."
      end

      def slice_range(arguments, total)
        from = Integer(arguments["start_line"].to_s, exception: false)
        to = Integer(arguments["end_line"].to_s, exception: false) || from
        return [ 1, [ total, LINE_LIMIT ].min ] unless from

        from = (from - CONTEXT_LINES).clamp(1, total)
        to = (to + CONTEXT_LINES).clamp(from, total)
        to = [ to, from + LINE_LIMIT - 1 ].min
        [ from, to ]
      end

      def format_blame(blame_lines)
        rendered = blame_lines.map do |entry|
          format("L%-5d %s %s %s (%s)", entry.line, entry.sha[0, 8], entry.date, entry.summary, entry.author)
        end
        distinct = blame_lines.map { |entry| entry.sha[0, 8] }.uniq

        "#{rendered.join("\n")}\n\nCommits touching this range: #{distinct.join(', ')}. " \
          "Use commit_lookup or pr_lookup for the full change."
      end

      def path_argument(arguments)
        path = arguments["path"].to_s
        fail! "path must be a relative path inside the repository" unless path.match?(PATH_FORMAT) && !path.include?("..")
        fail! "that path is not readable" if path.match?(SENSITIVE_PATHS)

        path
      end

      def repo_argument(arguments)
        repo = arguments["repo"].to_s
        fail! "repo must be in owner/name form" unless repo.match?(REPO_FORMAT)

        repo
      end

      def file_lines(files, total)
        listed = Array(files).first(FILE_LIMIT)
        lines = listed.map { |file| "  #{file['filename']} (+#{file['additions']} -#{file['deletions']})" }
        lines << "  ... #{total.to_i - listed.size} more files" if total.to_i > listed.size
        lines.join("\n")
      end
    end
  end
end
