module Integrations
  module Packs
    # Pull requests, deploys, file reads and blame come from GitHub's API. Reading code by search, definition, history
    # and language server happens in the run's sandbox, see Github::Code.
    class Github < NativePack
      Code = CodeHost::Code
      include CodeHost
      include Code
      include Fixing
      include Libraries
      include Actions
      include Asking
      include PullRequests
      include RepositoryIssues
      include Checks
      include Releases
      include Branches
      include Security

      REPO_FORMAT = /\A[\w.\-]+\/[\w.\-]+\z/
      FILE_LIMIT = 30
      # Each deployment needs a second call for its state.
      DEPLOYMENT_LIMIT = 3
      MAX_DEPLOYMENTS = 20
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
               "deployment_environment" => { "type" => "string", "description" => "Limit to one deployment environment, e.g. production (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT}, at most #{MAX_DEPLOYMENTS})" }
             },
             "required" => [ "repo" ]
           },
           read_only: true

      RUNNING_COMMIT = "running_commit".freeze
      CHANGES_BEFORE = "changes_before".freeze
      LIST_REPOSITORIES = "list_repositories".freeze
      DEFAULT_WINDOW_HOURS = 6
      MAX_WINDOW_HOURS = 24 * 14

      tool CHANGES_BEFORE,
           description: "What changed before a time, across every repository this connection can see, ranked by how likely " \
                        "each change is to have caused a failure that started then, with the reasons shown. Give whatever " \
                        "clues you have: repository or service names, stack trace frames as path:line, error text, a commit. " \
                        "It finds which repositories they point at, reads every deploy and merge in the window, blames the " \
                        "failing lines however long ago they changed, summarises the week before for a slow burn, and says " \
                        "what it could not check",
           params_schema: {
             "type" => "object",
             "properties" => {
               "at" => { "type" => "string", "description" => "When the failure started, as ISO 8601" },
               "window_hours" => { "type" => "integer", "description" => "How far back to read every change in detail (optional, #{DEFAULT_WINDOW_HOURS} hours)" },
               "repositories" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Repositories in owner/name form the clues name (optional)" },
               "names" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Service or app names mentioned, e.g. checkout (optional)" },
               "paths" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Stack trace frames as path:line, e.g. app/models/pool.rb:42 (optional)" },
               "error_texts" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Error names or messages as written in code, e.g. PoolExhausted (optional)" },
               "commits" => { "type" => "array", "items" => { "type" => "string" }, "description" => "A commit SHA an alert named as running (optional)" },
               "started_from" => { "type" => "string", "description" => "How the start time was chosen, e.g. first alert received (optional)" }
             },
             "required" => [ "at" ]
           },
           read_only: true

      tool LIST_REPOSITORIES,
           description: "List the repositories this GitHub connection can see, with each one's default branch and last push",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

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

      READ = "read".freeze
      WRITE = "write".freeze
      # A permission held at a level covers every lower one.
      LEVELS = { READ => 1, WRITE => 2, "admin" => 3 }.freeze
      # The permissions as GitHub's App settings name them, by the key an installation's permissions use.
      PERMISSION_NAMES = {
        "actions" => "Actions", "administration" => "Administration", "checks" => "Checks", "contents" => "Contents", "deployments" => "Deployments",
        "issues" => "Issues", "pull_requests" => "Pull requests", "statuses" => "Commit statuses", "vulnerability_alerts" => "Dependabot alerts",
        "security_events" => "Code scanning alerts", "secret_scanning_alerts" => "Secret scanning alerts", "workflows" => "Workflows"
      }.freeze
      # The permissions each tool cannot answer without, from GitHub's list of the permission every REST endpoint needs
      # (docs.github.com, REST API, Permissions required for GitHub Apps). A tool that reads a further endpoint only to
      # add to its answer, and says so when GitHub refuses it, names only what it cannot do without. Code is read by
      # cloning, which needs Contents read, and blame is GraphQL over the repository's contents. list_repositories reads
      # /installation/repositories and library_source reads public package sources, so neither needs one. fix_code
      # commits through the Git database (blobs, trees, commits, refs) and opens a pull request, and GitHub asks for
      # Workflows write besides when the change touches a workflow file, which only the change itself shows. A pull request
      # is an issue to GitHub, so its comments and labels go through issues/{number}, which takes Pull requests write for
      # one. Merging (PUT pulls/{number}/merge) and draft releases (POST releases) are Contents write, and a branch's
      # rules (rules/branches/{branch}) and tags are Metadata, which every App holds. pr_lookup, branch_protection and
      # ref_checks read checks, statuses, Dependabot alerts and branch protection only to add to their answer.
      NEEDS = {
        "pr_lookup" => { "pull_requests" => READ },
        "commit_lookup" => { "contents" => READ },
        "recent_deployments" => { "deployments" => READ },
        "changes_before" => { "contents" => READ },
        "list_repositories" => {},
        "running_commit" => { "deployments" => READ, "contents" => READ },
        "compare_commits" => { "contents" => READ },
        "merged_pull_requests" => { "pull_requests" => READ },
        "fetch_file" => { "contents" => READ },
        "blame" => { "contents" => READ },
        "list_workflows" => { "actions" => READ },
        "workflow_runs" => { "actions" => READ },
        "workflow_jobs" => { "actions" => READ },
        "job_log" => { "actions" => READ },
        "ci_status" => { "actions" => READ, "deployments" => READ },
        "rerun_workflow" => { "actions" => WRITE },
        "run_workflow" => { "actions" => WRITE, "contents" => READ },
        "cancel_workflow" => { "actions" => WRITE },
        "fix_code" => { "contents" => WRITE, "pull_requests" => WRITE },
        "list_pull_requests" => { "pull_requests" => READ },
        "pull_request_diff" => { "pull_requests" => READ },
        "comment_on_pull_request" => { "pull_requests" => WRITE },
        "reply_to_review_comment" => { "pull_requests" => WRITE },
        "review_pull_request" => { "pull_requests" => WRITE },
        "update_pull_request" => { "pull_requests" => WRITE },
        "request_reviewers" => { "pull_requests" => WRITE },
        "label_pull_request" => { "pull_requests" => WRITE },
        "close_pull_request" => { "pull_requests" => WRITE },
        "reopen_pull_request" => { "pull_requests" => WRITE },
        "merge_pull_request" => { "contents" => WRITE, "pull_requests" => READ },
        "update_pull_request_branch" => { "pull_requests" => WRITE },
        "list_issues" => { "issues" => READ },
        "issue_lookup" => { "issues" => READ },
        "create_issue" => { "issues" => WRITE },
        "comment_on_issue" => { "issues" => WRITE },
        "update_issue" => { "issues" => WRITE },
        "label_issue" => { "issues" => WRITE },
        "assign_issue" => { "issues" => WRITE },
        "close_issue" => { "issues" => WRITE },
        "reopen_issue" => { "issues" => WRITE },
        "ref_checks" => { "checks" => READ },
        "list_releases" => { "contents" => READ },
        "release_lookup" => { "contents" => READ },
        "list_tags" => {},
        "create_draft_release" => { "contents" => WRITE },
        "list_branches" => { "contents" => READ },
        "branch_protection" => { "contents" => READ },
        "create_branch" => { "contents" => WRITE },
        "delete_branch" => { "contents" => WRITE, "pull_requests" => READ },
        "dependabot_alerts" => { "vulnerability_alerts" => READ },
        "dependabot_alert" => { "vulnerability_alerts" => READ },
        "dismiss_dependabot_alert" => { "vulnerability_alerts" => WRITE },
        "reopen_dependabot_alert" => { "vulnerability_alerts" => WRITE },
        "code_scanning_alerts" => { "security_events" => READ },
        "code_scanning_alert" => { "security_events" => READ },
        "secret_scanning_alerts" => { "secret_scanning_alerts" => READ },
        "secret_scanning_alert" => { "secret_scanning_alerts" => READ },
        "library_source" => {},
        "list_files" => { "contents" => READ },
        "code_search" => { "contents" => READ },
        "find_definition" => { "contents" => READ },
        "find_usages" => { "contents" => READ },
        "git_log" => { "contents" => READ },
        "show_commit" => { "contents" => READ },
        "diff_refs" => { "contents" => READ },
        "ask_language_server" => { "contents" => READ },
        "run_shell" => { "contents" => READ },
        "run_tests" => { "contents" => READ }
      }.freeze

      # The installation a connection was made through, as Integrations::Installations reads it. One that is suspended
      # cannot mint a token, and one that shares no repository is read with a token, since only that lists them.
      def self.installation(environment_row)
        found = GithubApp.installation(environment_row)
        return Installations::Installation.new(state: Installations::REMOVED) unless found

        state = found["suspended_at"].present? ? Installations::SUSPENDED : (Installations::EMPTIED if shares_nothing?(environment_row))
        Installations::Installation.new(state: state, account: found.dig("account", "login"), page: found["html_url"], access: found["permissions"])
      end

      def self.shares_nothing?(environment_row)
        GithubApp.get("/installation/repositories?per_page=1", token: GithubApp.installation_token(environment_row))["total_count"].to_i.zero?
      end

      def self.uninstall(environment_row) = GithubApp.uninstall(environment_row)

      def self.forget_access(environment_row) = GithubApp.forget_token!(environment_row)

      def self.app_name = "GitHub App"

      def self.reach_name = "repositories"

      # What the tool needs that the installation's permissions leave out, such as "Actions read and write".
      def self.missing_access(environment_row, tool_name)
        granted = ConnectionSettings.of(environment_row).installation_access
        return [] unless granted.is_a?(Hash)

        NEEDS.fetch(tool_name.to_s, {}).reject { |permission, level| LEVELS.fetch(granted[permission].to_s, 0) >= LEVELS.fetch(level) }
             .map { |permission, level| permission_words(permission, level) }
      end

      def self.permission_words(permission, level) = "#{PERMISSION_NAMES.fetch(permission)} #{level == WRITE ? 'read and write' : 'read'}"

      # What a tool needs, said as the App's settings name it, for a refusal GitHub gave before the stored access knew.
      def self.needs_sentence(tool_name)
        needed = NEEDS.fetch(tool_name.to_s, {}).map { |permission, level| permission_words(permission, level) }
        "Firefight's GitHub App needs #{needed.any? ? needed.to_sentence : 'a permission it was not given'} on this installation for that."
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

      def changes_before(environment_row:, arguments:)
        started = time_argument(arguments, "at")
        hours = Integer(arguments["window_hours"].presence || DEFAULT_WINDOW_HOURS, exception: false)
        fail! "window_hours must be a whole number from 1 to #{MAX_WINDOW_HOURS}" unless hours&.between?(1, MAX_WINDOW_HOURS)

        ChangesBefore.new(
          token: GithubApp.installation_token(environment_row), started: started, window: hours.hours, clues: given_clues(arguments)
        ).text
      end

      def list_repositories(environment_row:, arguments:)
        token = GithubApp.installation_token(environment_row)
        body = GithubApp.get("/installation/repositories?per_page=100", token: token)
        listed = Array(body["repositories"]).map do |repository|
          "#{repository['full_name']}  default branch #{repository['default_branch']}  last push #{repository['pushed_at']}"
        end
        more = body["total_count"].to_i > listed.size ? "\n#{body['total_count'].to_i - listed.size} more not listed." : ""
        listed.empty? ? "This connection can see no repositories." : "#{listed.join("\n")}#{more}"
      end

      def compare_commits(environment_row:, arguments:)
        repo = repo_argument(arguments)
        base = ref_argument(arguments, "base", required: true)
        head = ref_argument(arguments, "head", required: true)
        token = GithubApp.installation_token(environment_row)

        comparison = GithubApp.get("/repos/#{repo}/compare/#{base}...#{head}", token: token)
        comparison_text(repo, comparison, token)
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

      # The repositories this connection sees, and the infrastructure defined as code in them, so the map knows what
      # each repository manages. Read once a day, and on Sync now.
      EVERY = 1.day
      MAX_REPOSITORY_PAGES = 10

      def map_of(environment_row)
        token = GithubApp.installation_token(environment_row)
        repositories, total = installation_repositories(token)
        listing = ResourceMap::Gap.new(text: "Only the first #{repositories.size} of #{total} repositories were listed.", kinds: [ ResourceMap::KIND_REPOSITORY ])
        repositories_snapshot(repositories, token, gaps: repositories.size >= total ? [] : [ listing ])
      end

      # Only the repository a change named, read again as the sweep reads it, with its infrastructure files. Gone only when
      # GitHub answers not found for it, which it also answers for one the installation no longer sees. nil for a scope
      # GitHub cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        name = scope.external_id
        return unless name&.match?(REPO_FORMAT) && [ nil, ResourceMap::KIND_REPOSITORY ].include?(scope.kind)

        token = GithubApp.installation_token(environment_row)
        repository = begin
          GithubApp.get("/repos/#{name}", token: token)
        rescue GithubApp::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ GithubApp::PROVIDER_KEY, name.split("/").first, ResourceMap::KIND_REPOSITORY, name ] ])
        end
        repositories_snapshot([ repository ], token)
      end

      # The repositories as the map has them, with the infrastructure defined as code in them. A file left unread holds
      # back a suggestion, never a resource.
      def repositories_snapshot(repositories, token, gaps: [])
        infrastructure = Infrastructure.new(token)
        files = infrastructure.files(repositories)
        unread_files = infrastructure.gaps.map { |text| ResourceMap::Gap.new(text: text, kinds: []) }
        found = repositories.map do |repository|
          ResourceMap::Found.new(provider: GithubApp::PROVIDER_KEY, account: repository["full_name"].split("/").first, kind: ResourceMap::KIND_REPOSITORY,
                                 external_id: repository["full_name"], name: repository["full_name"], url: repository["html_url"],
                                 details: { "branch" => repository["default_branch"] }.compact)
        end
        ResourceMap::Snapshot.new(resources: found, gaps: [ *gaps, *unread_files ], code_files: files, code_read: infrastructure.read_in_full)
      end
      private :repositories_snapshot

      def installation_repositories(token)
        listed = []
        total = 0
        (1..MAX_REPOSITORY_PAGES).each do |page|
          body = GithubApp.get("/installation/repositories?per_page=100&page=#{page}", token: token)
          total = body["total_count"].to_i
          listed.concat(Array(body["repositories"]))
          break if listed.size >= total || Array(body["repositories"]).empty?
        end
        [ listed, total ]
      end

      def check_health!(environment_row)
        GithubApp.installation_token(environment_row)
      end

      # The repositories a definition is looked for in when none is named.
      def visible_repositories(environment_row)
        Array(GithubApp.get("/installation/repositories?per_page=100", token: GithubApp.installation_token(environment_row))["repositories"]).map { |repository| repository["full_name"] }
      end

      # GitHub's repositories, fetched with the installation's token as GitHub asks for one (x-access-token).
      def code_remote(environment_row)
        CodeReading::Remote.new(root: "https://github.com", user: "x-access-token", token: -> { GithubApp.installation_token(environment_row).to_s })
      end

      private

      # ConnectionToolFactory strips "environment" from arguments before a pack sees it.
      def deployment_query(arguments)
        query = { "per_page" => whole_number_argument(arguments, "limit", DEPLOYMENT_LIMIT, MAX_DEPLOYMENTS) }
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


      def blame_ranges(repo, path, expression, token)
        GithubApp.blame(repo, path, expression, token: token)
      rescue GithubApp::Error => error
        fail! Sentence.join("Could not blame '#{path}'", error)
      end

      # Newest first, only those created by the time asked about, and only those whose own last status says they worked.
      def succeeded_deployments(repo, at, environment, token)
        deployments = Array(GithubApp.get("/repos/#{repo}/deployments?#{{ 'per_page' => DEPLOYMENT_CANDIDATES }.to_query}", token: token))
        before = deployments.select { |deployment| Time.zone.parse(deployment["created_at"].to_s)&.<=(at) }
        in_scope = scoped_to_environment(before, environment)

        in_scope.lazy.filter_map do |deployment|
          at = GithubApp.deployment_succeeded_at(repo, deployment["id"], token: token)
          deployment.merge("succeeded_at" => at.iso8601) if at
        end.first(2)
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
          "Source: a deploy record. #{running['environment']} deployment succeeded #{running['succeeded_at']} " \
            "by #{running.dig('creator', 'login') || 'unknown'}, ref #{running['ref']}."
        ]
        if previous
          lines << "Deployed before it: #{previous['sha']}, succeeded #{previous['succeeded_at']}."
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

      # What the agent or the first step passed, in the shape the clue reader gives, each marked as given.
      def given_clues(arguments)
        listed = ->(key) { Array(arguments[key]).map { |value| { "value" => value.to_s.strip, "source" => "what was given" } }.reject { |clue| clue["value"].empty? } }
        frames = Array(arguments["paths"]).filter_map do |frame|
          path, line = frame.to_s.strip.split(":", 2)
          { "value" => path.delete_prefix("/"), "line" => line.to_i, "source" => "what was given" } if path.present?
        end
        {
          "started" => { "source" => arguments["started_from"].presence || "the time given", "estimated" => false },
          "repositories" => listed.call("repositories").filter_map { |clue| clue.merge("value" => CodeChange.repository_name(clue["value"])) if CodeChange.repository_name(clue["value"]) },
          "names" => listed.call("names"), "paths" => frames, "error_texts" => listed.call("error_texts"), "commits" => listed.call("commits")
        }
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
