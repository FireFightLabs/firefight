module Integrations
  module Packs
    # File reads and blame come from GitHub's API at a given commit. Search still runs against a local clone through git
    # object commands only, so repo content never touches the filesystem API.
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
      # Deployments before the incident are walked newest first until one that succeeded.
      DEPLOYMENT_CANDIDATES = 30
      # With no deploy record, what reached the default branch in this window is what may have changed.
      NO_DEPLOY_LOOKBACK = 24.hours
      # Each commit costs a call to find its pull request, so the newest ones are looked up and the rest are counted.
      PULL_LOOKUP_LIMIT = 25
      CODEOWNERS_PATHS = [ ".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS" ].freeze
      PRODUCTION = /\Aprod/i
      REF_FORMAT = %r{\A[\w.\-/]+\z}

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

      RUNNING_COMMIT = "running_commit".freeze

      tool RUNNING_COMMIT,
           description: "Which commit was running at a given time: the last deploy that succeeded before it, and the one before " \
                        "that to compare against. Without a deploy record it falls back to the default branch at that time and " \
                        "says so, since a merge is not proof of a deploy",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "at" => { "type" => "string", "description" => "The time, as ISO 8601, usually when the incident started" },
               "deployment_environment" => { "type" => "string", "description" => "The deployment environment, e.g. production (optional, production when there is one)" }
             },
             "required" => [ "repo", "at" ]
           },
           read_only: true

      tool :compare_commits,
           description: "What changed between two commits: the commits and pull requests with their authors and reviewers, " \
                        "the changed files grouped by kind with migrations, config and dependencies first, dependency bumps " \
                        "in plain words, who owns the changed files, and every diff",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "base" => { "type" => "string", "description" => "The earlier commit SHA, branch or tag" },
               "head" => { "type" => "string", "description" => "The later commit SHA, branch or tag" }
             },
             "required" => [ "repo", "base", "head" ]
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
           description: "Read a file from the repository at a given commit, optionally sliced to a line range with surrounding context",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "path" => { "type" => "string", "description" => "File path within the repository" },
               "ref" => { "type" => "string", "description" => "Commit SHA, branch or tag to read at, usually the running commit (optional, the default branch otherwise)" },
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
           description: "Attribute a line range, as it stood at a given commit, to the commits and pull requests that last touched it",
           params_schema: {
             "type" => "object",
             "properties" => {
               "repo" => { "type" => "string", "description" => "Repository in owner/name form, e.g. acme/checkout" },
               "path" => { "type" => "string", "description" => "File path within the repository" },
               "ref" => { "type" => "string", "description" => "Commit SHA, branch or tag, usually the running commit (optional, the default branch otherwise)" },
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
        ref = ref_argument(arguments)
        token = GithubApp.installation_token(environment_row)

        lines = read_file_lines(repo, path, ref, token)
        from, to = slice_range(arguments, lines.size)
        numbered = lines[(from - 1)..(to - 1)].each_with_index.map do |line, index|
          format("%4d  %s", from + index, line.chomp)
        end

        "#{path}:#{from}-#{to} (of #{lines.size} lines) at #{ref || 'the default branch'}\n" \
          "#{permalink(repo, path, ref, from, to)}\n#{numbered.join("\n")}"
      end

      def running_commit(environment_row:, arguments:)
        repo = repo_argument(arguments)
        at = time_argument(arguments, "at")
        token = GithubApp.installation_token(environment_row)

        deployed = succeeded_deployments(repo, at, arguments["deployment_environment"].to_s, token).first(2)
        return deployed_text(repo, at, *deployed) if deployed.any?

        default_branch_text(repo, at, token)
      end

      def compare_commits(environment_row:, arguments:)
        repo = repo_argument(arguments)
        base = ref_argument(arguments, "base", required: true)
        head = ref_argument(arguments, "head", required: true)
        token = GithubApp.installation_token(environment_row)

        comparison = GithubApp.get("/repos/#{repo}/compare/#{base}...#{head}", token: token)
        comparison_text(repo, comparison, token)
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

        ref = ref_argument(arguments)
        token = GithubApp.installation_token(environment_row)
        ranges = blame_ranges(repo, path, ref || "HEAD", token).select { |range| range["startingLine"] <= to && range["endingLine"] >= from }
        fail! "No blame for '#{path}' at #{ref || 'the default branch'}." if ranges.empty?

        format_blame(repo, path, ref, ranges, from, to)
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

      def read_file_lines(repo, path, ref, token)
        query = ref ? "?#{{ 'ref' => ref }.to_query}" : ""
        file = GithubApp.get("/repos/#{repo}/contents/#{path}#{query}", token: token)
        fail! "'#{path}' is a directory, not a file." if file.is_a?(Array)

        Base64.decode64(file["content"].to_s).force_encoding(Encoding::UTF_8).scrub.lines
      rescue GithubApp::Error
        fail! "No file at '#{path}' #{ref ? "at #{ref}" : 'on the default branch'}."
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

      def blame_ranges(repo, path, expression, token)
        owner, name = repo.split("/", 2)
        data = GithubApp.graphql(BLAME_QUERY, { owner: owner, name: name, expression: expression, path: path }, token: token)
        Array(data.dig("repository", "object", "blame", "ranges"))
      rescue GithubApp::Error => error
        fail! "Could not blame '#{path}': #{error.message}"
      end

      # Newest first, only those created by the time asked about, and only those whose own last status says they worked.
      def succeeded_deployments(repo, at, environment, token)
        deployments = Array(GithubApp.get("/repos/#{repo}/deployments?#{{ 'per_page' => DEPLOYMENT_CANDIDATES }.to_query}", token: token))
        before = deployments.select { |deployment| Time.zone.parse(deployment["created_at"].to_s)&.<=(at) }
        in_scope = scoped_to_environment(before, environment)

        in_scope.lazy.select { |deployment| deployment_state(repo, deployment["id"], token) == "success" }.first(2)
      end

      # An environment asked for by name, else anything that looks like production, else every environment.
      def scoped_to_environment(deployments, environment)
        return deployments.select { |deployment| deployment["environment"].to_s.casecmp?(environment) } if environment.present?

        production = deployments.select { |deployment| deployment["environment"].to_s.match?(PRODUCTION) }
        production.presence || deployments
      end

      def deployed_text(repo, at, running, previous = nil)
        lines = [
          "Running in #{repo} at #{at.iso8601}: #{running['sha']}",
          "Source: a deploy record. #{running['environment']} deployment created #{running['created_at']} " \
            "by #{running.dig('creator', 'login') || 'unknown'}, ref #{running['ref']}, status success."
        ]
        if previous
          lines << "Deployed before it: #{previous['sha']} at #{previous['created_at']}."
          lines << "What this deploy changed: compare_commits with base #{previous['sha']} and head #{running['sha']}."
        else
          lines << "No earlier successful deployment is recorded, so there is nothing to compare this deploy against."
        end
        lines.join("\n")
      end

      def default_branch_text(repo, at, token)
        branch = GithubApp.get("/repos/#{repo}", token: token)["default_branch"]
        head = commit_on_branch_at(repo, branch, at, token)
        fail! "No commit on #{branch} before #{at.iso8601}." unless head

        earlier_at = at - NO_DEPLOY_LOOKBACK
        base = commit_on_branch_at(repo, branch, earlier_at, token)
        lines = [
          "Running in #{repo} at #{at.iso8601}: not known. There is no successful deploy record before then.",
          "Tip of #{branch} at that time: #{head['sha']} (#{head.dig('commit', 'committer', 'date')}).",
          "This is a guess from the default branch, not proof it was deployed. Say so when relying on it."
        ]
        if base && base["sha"] != head["sha"]
          lines << "What reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before: compare_commits with base #{base['sha']} and head #{head['sha']}."
        else
          lines << "Nothing reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before."
        end
        lines.join("\n")
      end

      def commit_on_branch_at(repo, branch, at, token)
        query = { "sha" => branch, "until" => at.iso8601, "per_page" => 1 }.to_query
        Array(GithubApp.get("/repos/#{repo}/commits?#{query}", token: token)).first
      end

      def comparison_text(repo, comparison, token)
        commits = Array(comparison["commits"])
        files = Array(comparison["files"])
        head = commits.last&.dig("sha") || comparison.dig("merge_base_commit", "sha")
        owners = code_owners(repo, head, token)

        [
          "#{commits.size} commits, #{files.size} files changed. Base #{comparison.dig('base_commit', 'sha')}, head #{head}.",
          grouped_files(files),
          dependency_text(files),
          pull_requests_text(repo, commits, token),
          owners_text(files, owners),
          diffs_text(repo, head, files)
        ].compact.join("\n\n")
      end

      def grouped_files(files)
        groups = files.group_by { |file| CodeChange.kind_for(file["filename"]) }
        sections = CodeChange::KINDS.filter_map do |kind|
          next unless groups[kind]

          listed = groups[kind].map { |file| "  #{file['filename']} (#{file['status']}, +#{file['additions']} -#{file['deletions']})" }
          "#{CodeChange::KIND_LABELS.fetch(kind)}:\n#{listed.join("\n")}"
        end
        "Changed files, most likely to matter first:\n#{sections.join("\n")}"
      end

      def dependency_text(files)
        bumps = files.flat_map { |file| CodeChange::DependencyBumps.from(file["filename"], file["patch"]) }
        return nil if bumps.empty?

        "Dependency changes:\n#{bumps.map { |bump| "  #{bump}" }.join("\n")}"
      end

      # Newest commits first, one pull request each, so a long range still names who to ask about the latest changes.
      def pull_requests_text(repo, commits, token)
        looked_up = commits.last(PULL_LOOKUP_LIMIT).reverse
        pulls = looked_up.flat_map { |commit| pulls_for(repo, commit["sha"], token) }.uniq { |pull| pull["number"] }
        lines = commits.reverse.map { |commit| commit_line(commit) }
        text = "Commits, newest first:\n#{lines.join("\n")}"
        text += "\n\nPull requests:\n#{pulls.map { |pull| pull_line(repo, pull, token) }.join("\n")}" if pulls.any?
        text += "\n(Pull requests looked up for the newest #{PULL_LOOKUP_LIMIT} commits of #{commits.size}.)" if commits.size > PULL_LOOKUP_LIMIT
        text
      end

      def pulls_for(repo, sha, token)
        Array(GithubApp.get("/repos/#{repo}/commits/#{sha}/pulls", token: token))
      rescue GithubApp::Error
        []
      end

      def commit_line(commit)
        "  #{commit['sha'][0, 12]}  #{commit.dig('commit', 'author', 'date')}  " \
          "#{commit.dig('author', 'login') || commit.dig('commit', 'author', 'name')}  #{commit.dig('commit', 'message').to_s.lines.first&.strip}"
      end

      def pull_line(repo, pull, token)
        reviewers = reviewers_of(repo, pull["number"], token)
        "  PR ##{pull['number']} #{pull['title']} by #{pull.dig('user', 'login')}" \
          "#{reviewers.any? ? ", reviewed by #{reviewers.join(', ')}" : ', no reviews'} #{pull['html_url']}"
      end

      def reviewers_of(repo, number, token)
        Array(GithubApp.get("/repos/#{repo}/pulls/#{number}/reviews", token: token)).filter_map { |review| review.dig("user", "login") }.uniq
      rescue GithubApp::Error
        []
      end

      def code_owners(repo, ref, token)
        CODEOWNERS_PATHS.each do |path|
          lines = read_file_lines(repo, path, ref, token)
          return CodeChange::Owners.new(lines.join)
        rescue NativePack::Error
          next
        end
        nil
      end

      def owners_text(files, owners)
        return "No CODEOWNERS file, so no owners are named." unless owners

        by_owner = files.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |file, grouped|
          owners.for(file["filename"]).each { |owner| grouped[owner] << file["filename"] }
        end
        return "CODEOWNERS names no owner for these files." if by_owner.empty?

        "Owners of the changed files, from CODEOWNERS:\n#{by_owner.map { |owner, paths| "  #{owner}: #{paths.join(', ')}" }.join("\n")}"
      end

      # Most likely to matter first, the same order as the grouping.
      def diffs_text(repo, head, files)
        ordered = files.sort_by { |file| CodeChange::KINDS.index(CodeChange.kind_for(file["filename"])) }
        diffs = ordered.map do |file|
          body = file["patch"].presence || "(no text diff, binary or too large for GitHub to show)"
          "#{file['filename']} #{permalink(repo, file['filename'], head)}\n#{body}"
        end
        "Diffs:\n\n#{diffs.join("\n\n")}"
      end

      # Pinned to the commit, so the link still shows these lines after the file changes.
      def permalink(repo, path, ref, from = nil, to = nil)
        anchor = from ? "#L#{from}#{"-L#{to}" if to && to != from}" : ""
        "https://github.com/#{repo}/blob/#{ref || 'HEAD'}/#{path}#{anchor}"
      end

      def ref_argument(arguments, key = "ref", required: false)
        ref = arguments[key].to_s.strip
        fail! "#{key} is required" if ref.blank? && required
        return nil if ref.blank?
        fail! "#{key} must be a commit SHA, branch or tag" unless ref.match?(REF_FORMAT) && !ref.include?("..")

        ref
      end

      def time_argument(arguments, key)
        Time.iso8601(arguments[key].to_s)
      rescue ArgumentError
        fail! "#{key} must be an ISO 8601 time, for example 2026-09-12T09:00:00Z"
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

      def format_blame(repo, path, ref, ranges, from, to)
        rendered = ranges.map do |range|
          commit = range["commit"]
          lines = "L#{[ range['startingLine'], from ].max}-#{[ range['endingLine'], to ].min}"
          pull = commit.dig("associatedPullRequests", "nodes", 0)
          who = commit.dig("author", "user", "login") || commit.dig("author", "name")
          "#{lines.ljust(12)} #{commit['oid'][0, 12]} #{commit['committedDate']} #{commit['messageHeadline']} (#{who})" \
            "#{" PR ##{pull['number']}" if pull}"
        end
        distinct = ranges.map { |range| range.dig("commit", "oid")[0, 12] }.uniq

        "#{path}:#{from}-#{to} at #{ref || 'the default branch'} #{permalink(repo, path, ref, from, to)}\n" \
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
