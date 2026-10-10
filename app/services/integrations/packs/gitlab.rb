module Integrations
  module Packs
    # GitLab, on GitLab.com or a workspace's own instance, read with an access token through GitLab's REST API (doc/api in
    # gitlab-org/gitlab): merge requests, commits, deployments, pipelines and their jobs, files and blame. Reading code by
    # search, definition, history and language server happens in the run's sandbox (CodeHost::Code), and the pipelines
    # tools live in Gitlab::Pipelines. Every tool only reads but the sandbox's test runner and the ones that retry, run or
    # cancel a pipeline.
    class Gitlab < NativePack
      # The environment row's credentials, which only this pack reads.
      URL = "url".freeze
      TOKEN = "token".freeze

      PROVIDER = "GitLab".freeze
      PROVIDER_KEY = "gitlab".freeze
      # A project's path holds its groups, so a code tool names one the way GitLab shows it.
      REPO_PARAM = { "type" => "string", "description" => "Project path with its groups, e.g. acme/platform/checkout" }.freeze
      REPOS_PARAM = { "type" => "array", "items" => { "type" => "string" }, "description" => "Project paths with their groups (optional, every project this connection can see)" }.freeze

      Code = CodeHost::Code
      include CodeHost
      include Code
      include Pipelines
      include CiConfig

      REPO_FORMAT = %r{\A[\w.\-]+(/[\w.\-]+)+\z}
      SHA_FORMAT = /\A\h{6,40}\z/
      # Scopes an access token needs: the API to read, and the repository to fetch for the code sandbox. api covers both.
      READ_SCOPES = [ %w[read_api api], %w[read_repository write_repository api] ].freeze
      FILE_LIMIT = 30
      MERGED_LIMIT = 10
      MERGED_CANDIDATES = 50
      DEPLOYMENT_LIMIT = 10
      MAX_DEPLOYMENTS = 50
      DEPLOYMENT_CANDIDATES = 30
      NO_DEPLOY_LOOKBACK = 24.hours
      PULL_LOOKUP_LIMIT = 25
      BLAME_MERGE_REQUESTS = 5
      # GitLab reads CODEOWNERS from these places, the first found.
      CODEOWNERS_PATHS = [ "CODEOWNERS", "docs/CODEOWNERS", ".gitlab/CODEOWNERS" ].freeze
      MAX_PROJECT_PAGES = 10
      HEAD = "HEAD".freeze
      GIT_USER = "oauth2".freeze

      tool :list_projects,
           description: "List the projects this GitLab connection can see, with each one's default branch and last activity",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :mr_lookup,
           description: "Fetch a merge request: title, state, author, who merged it and when, its branches, who approved it, and the changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "iid" => { "type" => "integer", "description" => "The merge request's number in the project, as in !42" } }, %w[repo iid]),
           read_only: true

      tool :commit_lookup,
           description: "Fetch a commit: message, author, stats, and changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "sha" => { "type" => "string", "description" => "Commit SHA" } }, %w[repo sha]),
           read_only: true

      tool :recent_deployments,
           description: "List a project's deployments, newest first, each with the environment, the ref and commit deployed, the outcome, who ran it and its job",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "deployment_environment" => { "type" => "string", "description" => "Only this environment, by name, e.g. production (optional)" },
             "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT}, at most #{MAX_DEPLOYMENTS})" }
           }, %w[repo]),
           read_only: true

      tool :merged_merge_requests,
           description: "List merge requests merged into a project, newest first, optionally only those merged since a given time",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "since" => { "type" => "string", "description" => "Only merge requests merged at or after this time, as ISO 8601 (optional)" }
           }, %w[repo]),
           read_only: true

      tool :running_commit,
           description: "Which commit was running at a given time: the last deployment that succeeded before it, and the one before " \
                        "that to compare against. Without a deployment it falls back to the default branch at that time and " \
                        "says so, since a merge is not proof of a deploy",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "at" => { "type" => "string", "description" => "The time, as ISO 8601, usually when the incident started" },
             "deployment_environment" => { "type" => "string", "description" => "The environment, e.g. production (optional, production when there is one)" }
           }, %w[repo at]),
           read_only: true

      tool :compare_commits,
           description: "What changed between two commits: the commits and merge requests with their authors and approvers, " \
                        "the changed files grouped by kind with migrations, config and dependencies first, dependency bumps " \
                        "in plain words, who owns the changed files, and every diff",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "base" => { "type" => "string", "description" => "The earlier commit SHA, branch or tag" },
             "head" => { "type" => "string", "description" => "The later commit SHA, branch or tag" }
           }, %w[repo base head]),
           read_only: true

      tool :fetch_file,
           description: "Read a file from the project at a given commit, optionally sliced to a line range with surrounding context",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "path" => { "type" => "string", "description" => "File path within the project" },
             "ref" => Code::REF,
             "start_line" => { "type" => "integer", "description" => "First line of interest (optional, the slice includes context around it)" },
             "end_line" => { "type" => "integer", "description" => "Last line of interest (optional)" }
           }, %w[repo path]),
           read_only: true

      tool :blame,
           description: "Attribute a line range, as it stood at a given commit, to the commits and merge requests that last touched it",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "path" => { "type" => "string", "description" => "File path within the project" },
             "ref" => Code::REF,
             "start_line" => { "type" => "integer", "description" => "First line of the range" },
             "end_line" => { "type" => "integer", "description" => "Last line of the range" }
           }, %w[repo path start_line end_line]),
           read_only: true

      # A path written as GitLab's reference writes it may start with the API's own prefix, which the client adds.
      API_PREFIX = %r{\A/?api/v4(?=/|\z)}
      READ_SCHEMA = ApiReads.path_schema("/projects/<project id>/environments").deep_merge(
        "properties" => {
          "project" => { "type" => "string", "description" => "A project by its path with its groups, such as acme/platform/checkout, when the " \
                                                               "read is inside one. path is then what comes after /projects/<project>, such as " \
                                                               "/environments (optional)" }
        }
      ).freeze

      tool :api_read,
           description: "Anything else GitLab's REST API reads that the other GitLab tools do not cover, such as a project's environments " \
                        "and their protections, protected branches, releases, members, container registry, issues, or a group's " \
                        "settings. A GET to a path of GitLab's REST API (the instance's /api/v4), written after /api/v4 as the API " \
                        "reference the gitlab_api skill names writes it, such as /projects/<project id>/environments, or with " \
                        "project set and the path inside it. A list answers one page: pass per_page, at most 100, and page 2, 3 " \
                        "and on while a page comes back full. Only reads, so it never changes anything. CI/CD variables, pipeline " \
                        "triggers, integrations and webhooks come back as their names",
           params_schema: READ_SCHEMA,
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN, label: "Access token", secret: true, placeholder: "glpat-...",
                              hint: "A personal, group or project access token with the read_api and read_repository scopes. A group token reaches every project in its group. " \
                                    "Retrying, running or canceling a pipeline needs the api scope in place of read_api. So does following " \
                                    "changes live, with the Maintainer role on a project or the Owner role on a group on Premium or Ultimate.")
        ]
      end

      # Lists a project with the token, so a wrong address or token is said on the form before anything is saved, and a
      # personal access token missing a scope is named. The address is the url connect field, GitLab.com when blank.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[TOKEN].to_s.strip
        return "Paste an access token." if token.empty?

        api = GitlabApi.new(fields.to_h[URL], token)
        api.get("/projects", "membership" => true, "simple" => true, "per_page" => 1)
        missing = missing_scopes(api)
        "This token is missing the #{missing.to_sentence} #{'scope'.pluralize(missing.size)}. Create one with read_api and read_repository." if missing.any?
      rescue GitlabApi::Refused => error
        Sentence.join("GitLab refused this token", error, after: "Check it is active and has the read_api scope")
      rescue GitlabApi::Error => error
        Sentence.join("GitLab could not be reached with this address and token", error)
      end

      # Only a personal access token can say its own scopes (personal_access_tokens/self). A group or project token is a
      # bot's, and GitLab may refuse to say, so nothing is assumed missing then.
      def self.missing_scopes(api)
        token = api.get("/personal_access_tokens/self")
        scopes = token.is_a?(Hash) ? Array(token["scopes"]) : []
        return [] if scopes.empty?

        READ_SCOPES.reject { |accepted| scopes.intersect?(accepted) }.map(&:first)
      rescue GitlabApi::Error
        []
      end
      private_class_method :missing_scopes

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(TOKEN, values[TOKEN].to_s.strip)
      end

      def list_projects(environment_row:, arguments:)
        projects, more = api(environment_row).list("/projects", "membership" => true, "simple" => true, "order_by" => "last_activity_at")
        return "This connection can see no projects." if projects.empty?

        listed = projects.map { |project| "#{project['path_with_namespace']}  default branch #{project['default_branch'] || 'none'}  last activity #{project['last_activity_at']}" }
        "#{listed.join("\n")}#{"\nMore projects than these. Name one to read it." if more}"
      end

      def mr_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        iid = Integer(arguments["iid"].to_s, exception: false)
        fail! "iid must be the merge request's number" unless iid&.positive?

        gitlab = api(environment_row)
        request = gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}")
        diffs, more = gitlab.list("#{GitlabApi.project(repo)}/merge_requests/#{iid}/diffs")
        Telemetry.result(<<~TEXT, link: link(request["web_url"]))
          MR !#{request['iid']}: #{request['title']}
          State: #{merge_state(request)}
          Author: #{request.dig('author', 'username')}
          Branch: #{request['source_branch']} -> #{request['target_branch']}
          Approved by: #{approvers(gitlab, repo, iid).presence&.join(', ') || 'nobody'}
          Changes: #{request['changes_count'] || diffs.size} files

          #{file_lines(diffs.map { |diff| changed_file(diff) }, more)}
          #{request['description'].presence || '(no description)'}
        TEXT
      end

      def commit_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        sha = arguments["sha"].to_s
        fail! "sha must be a commit SHA" unless sha.match?(SHA_FORMAT)

        gitlab = api(environment_row)
        commit = gitlab.get("#{GitlabApi.project(repo)}/repository/commits/#{sha}")
        diffs, more = gitlab.list("#{GitlabApi.project(repo)}/repository/commits/#{sha}/diff")
        Telemetry.result(<<~TEXT, link: link(commit["web_url"]))
          Commit #{commit['id']}
          Author: #{commit['author_name']} at #{commit['authored_date']}
          Changes: +#{commit.dig('stats', 'additions')} -#{commit.dig('stats', 'deletions')}

          #{commit['message']}

          #{file_lines(diffs.map { |diff| changed_file(diff) }, more)}
        TEXT
      end

      def recent_deployments(environment_row:, arguments:)
        repo = repo_argument(arguments)
        limit = whole_number_argument(arguments, "limit", DEPLOYMENT_LIMIT, MAX_DEPLOYMENTS)
        query = { "order_by" => "id", "sort" => "desc", "per_page" => limit, "environment" => arguments["deployment_environment"].presence }
        deployments = Array(api(environment_row).get("#{GitlabApi.project(repo)}/deployments", query))
        return "No deployments recorded for #{repo}#{" in #{query['environment']}" if query['environment']}." if deployments.empty?

        deployments.map { |deployment| deployment_line(deployment) }.join("\n")
      end

      def merged_merge_requests(environment_row:, arguments:)
        repo = repo_argument(arguments)
        since = since_argument(arguments)
        # Ordered by update, which every GitLab version takes, and then by when each was merged.
        query = { "state" => "merged", "order_by" => "updated_at", "sort" => "desc", "per_page" => MERGED_CANDIDATES, "merged_after" => since&.iso8601 }
        merged = Array(api(environment_row).get("#{GitlabApi.project(repo)}/merge_requests", query))
                 .select { |request| request["merged_at"].present? }.sort_by { |request| request["merged_at"] }.reverse.first(MERGED_LIMIT)
        return "No merge requests merged#{since ? " since #{since.iso8601}" : ''} in #{repo}." if merged.empty?

        merged.map do |request|
          "MR !#{request['iid']}  #{request['title']}  merged #{request['merged_at']} by #{request.dig('merge_user', 'username') || 'unknown'} " \
            "into #{request['target_branch']}  #{request['web_url']}"
        end.join("\n")
      end

      def running_commit(environment_row:, arguments:)
        repo = repo_argument(arguments)
        at = time_argument(arguments, "at")
        gitlab = api(environment_row)
        # GitLab asks for both when reading deployments by when they finished.
        query = { "status" => "success", "order_by" => "finished_at", "sort" => "desc", "finished_before" => at.iso8601, "per_page" => DEPLOYMENT_CANDIDATES }
        deployed = scoped_to_environment(Array(gitlab.get("#{GitlabApi.project(repo)}/deployments", query)), arguments["deployment_environment"].to_s).first(2)
        return deployed_text(repo, at, *deployed) if deployed.any?

        default_branch_text(gitlab, repo, at)
      end

      def compare_commits(environment_row:, arguments:)
        repo = repo_argument(arguments)
        base = ref_argument(arguments, "base", required: true)
        head = ref_argument(arguments, "head", required: true)
        gitlab = api(environment_row)
        comparison = gitlab.get("#{GitlabApi.project(repo)}/repository/compare", "from" => base, "to" => head)
        comparison_text(gitlab, repo, base, comparison)
      end

      def fetch_file(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        ref = ref_argument(arguments)
        gitlab = api(environment_row)
        file = read_file(gitlab, repo, path, ref)
        lines = Base64.decode64(file["content"].to_s).force_encoding(Encoding::UTF_8).scrub.lines
        from, to = slice_range(arguments, lines.size)
        link = blob_link(gitlab, repo, file["commit_id"], path, from, to)
        Telemetry.result("#{path}:#{from}-#{to} (of #{lines.size} lines) at #{ref || 'the default branch'}, commit #{file['commit_id'].to_s[0, 12]}\n" \
                         "#{lines.empty? ? '(empty file)' : numbered(lines, from, to)}", link: link)
      end

      def blame(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        from, to = line_range!(arguments)
        ref = ref_argument(arguments)
        gitlab = api(environment_row)
        ranges = begin
          Array(gitlab.get("#{GitlabApi.file(repo, path)}/blame", "ref" => ref || HEAD, "range[start]" => from, "range[end]" => to))
        rescue GitlabApi::NotFound
          fail! "No file at '#{path}' #{ref ? "at #{ref}" : 'on the default branch'}."
        end
        fail! "No blame for '#{path}' at #{ref || 'the default branch'}." if ranges.empty?

        Telemetry.result(blame_text(gitlab, repo, path, ref, ranges, from, to), link: blob_link(gitlab, repo, ref || HEAD, path, from, to))
      end

      # Every project the token sees, and the infrastructure defined as code in them, so the map knows what each project
      # manages. Read once a day, and on Sync now.
      EVERY = 1.day

      def map_of(environment_row)
        gitlab = api(environment_row)
        projects, more = gitlab.list("/projects", { "membership" => true, "order_by" => "id", "sort" => "asc" }, pages: MAX_PROJECT_PAGES)
        listing = more ? [ ResourceMap::Gap.new(text: "Only the first #{projects.size} projects were listed.", kinds: [ ResourceMap::KIND_REPOSITORY ]) ] : []
        projects_snapshot(gitlab, projects, gaps: listing)
      end

      # Only the project a change named, read again as the sweep reads it, with its infrastructure files. Gone only when
      # GitLab answers not found for it. nil for a scope GitLab cannot narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        path = scope.external_id
        return unless path&.include?("/") && [ nil, ResourceMap::KIND_REPOSITORY ].include?(scope.kind)

        gitlab = api(environment_row)
        project = begin
          gitlab.get(GitlabApi.project(path))
        rescue GitlabApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, path.rpartition("/").first, ResourceMap::KIND_REPOSITORY, path ] ])
        end
        projects_snapshot(gitlab, [ project ])
      end

      # The projects as the map has them, with the infrastructure defined as code in them. A file left unread holds back a
      # suggestion, never a resource.
      def projects_snapshot(gitlab, projects, gaps: [])
        infrastructure = Infrastructure.new(gitlab)
        files = infrastructure.files(projects.map { |project| repository_of(project) })
        found = projects.map do |project|
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: project.dig("namespace", "full_path").presence || project["path_with_namespace"].split("/").first,
                                 kind: ResourceMap::KIND_REPOSITORY, external_id: project["path_with_namespace"], name: project["path_with_namespace"],
                                 url: project["web_url"], details: { "branch" => project["default_branch"] }.compact)
        end
        unread_files = infrastructure.gaps.map { |text| ResourceMap::Gap.new(text: text, kinds: []) }
        ResourceMap::Snapshot.new(resources: found, gaps: [ *gaps, *unread_files ], code_files: files, code_read: infrastructure.read_in_full)
      end
      private :projects_snapshot

      # A GET the read guard let through (ReadGuards::Gitlab). The token reaches only what its owner can read, which is
      # what the connection reads. A project named by its path is encoded into one segment here, since the guard takes
      # plain segments only.
      def api_read(environment_row:, arguments:)
        given = arguments.merge("path" => arguments["path"].to_s.strip.sub(API_PREFIX, ""))
        call = begin
          ReadGuards::Gitlab.reading(ApiReads::TOOL, given)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        project = arguments["project"].to_s.strip.delete_prefix("/").delete_suffix("/").presence
        fail! "project must be a project's path with its groups, such as acme/platform/checkout." if project && (!project.match?(REPO_FORMAT) || project.split("/").any? { |part| part.match?(/\A\.+\z/) })

        inside, query = call.values_at("path", "query")
        path = project ? "#{GitlabApi.project(project)}#{inside}" : inside
        gitlab = api(environment_row)
        answer = gitlab.read(path, query)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::Gitlab.secret?(inside), webhooks: ReadGuards::Gitlab.webhooks?(inside))
        page = (answer["web_url"].presence if answer.is_a?(Hash)) || (gitlab.web_url(project) if project)
        Telemetry.result(text, link: page && Telemetry::Link.new(provider: PROVIDER, url: page))
      rescue GitlabApi::Refused => error
        fail! Sentence.join("GitLab refused this read", error, after: "The token's role or scopes do not reach it")
      end

      def check_health!(environment_row)
        api(environment_row).get("/projects", "membership" => true, "simple" => true, "per_page" => 1)
      rescue GitlabApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(TOKEN)
        fail! "This environment has no GitLab token. Reconnect it on the Integrations page." if token.blank?

        GitlabApi.new(settings.field(URL), token)
      rescue GitlabApi::Error => error
        fail! error.message
      end

      # The repositories a definition is looked for in when none is named.
      def visible_repositories(environment_row)
        api(environment_row).list("/projects", "membership" => true, "simple" => true, "order_by" => "last_activity_at").first.map { |project| project["path_with_namespace"] }
      end

      # The sandbox fetches from the same instance, signing in as GitLab documents for an access token, and a host other
      # than GitLab.com is fetched at the address checked, never following a redirect elsewhere.
      def code_remote(environment_row)
        gitlab = api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(TOKEN)
        host = URI.parse(gitlab.base_url).host
        options = [ "http.followRedirects=false" ]
        address = gitlab.address
        options << "http.curloptResolve=#{host}:443:#{address}" if address
        CodeReading::Remote.new(host: host, root: gitlab.base_url, user: GIT_USER, token: -> { token }, options: options)
      end

      def repo_argument(arguments)
        repo = arguments["repo"].to_s
        fail! "repo must be a project's path with its groups, such as acme/checkout" unless repo.match?(REPO_FORMAT) && !repo.include?("..")

        repo
      end

      # A project in the shape the infrastructure reader and the sandbox take.
      def repository_of(project)
        { "id" => project["id"], "full_name" => project["path_with_namespace"], "default_branch" => project["default_branch"],
          "size" => project["empty_repo"] ? 0 : 1, "archived" => project["archived"] == true, "fork" => project["forked_from_project"].present? }
      end

      def link(url) = url.present? ? Telemetry::Link.new(provider: PROVIDER, url: url) : nil

      # Pinned to the commit, so the link still shows these lines after the file changes. GitLab writes a range as #L27-30.
      def blob_link(gitlab, repo, ref, path, from = nil, to = nil)
        anchor = from ? "#L#{from}#{"-#{to}" if to && to != from}" : ""
        link(gitlab.web_url(repo, "-", "blob", Http.segment(ref.to_s), *path.split("/").map { |part| Http.segment(part) }) + anchor)
      end

      def read_file(gitlab, repo, path, ref)
        gitlab.get(GitlabApi.file(repo, path), "ref" => ref || HEAD)
      rescue GitlabApi::NotFound
        fail! "No file at '#{path}' #{ref ? "at #{ref}" : 'on the default branch'}."
      end

      def merge_state(request)
        return "merged at #{request['merged_at']} by #{request.dig('merge_user', 'username') || 'unknown'}" if request["merged_at"]

        request["state"]
      end

      def approvers(gitlab, repo, iid)
        Array(gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}/approvals")["approved_by"]).filter_map { |approval| approval.dig("user", "username") }
      rescue GitlabApi::Error
        []
      end

      # A GitLab diff in the shape the change summaries read: filename, status, additions, deletions and patch.
      def changed_file(diff)
        status = if diff["new_file"] then "added"
        elsif diff["deleted_file"] then "removed"
        elsif diff["renamed_file"] then "renamed"
        else "modified"
        end
        patch = diff["diff"].to_s
        { "filename" => diff["new_path"], "status" => status, "patch" => patch,
          "additions" => patch.lines.count { |line| line.start_with?("+") && !line.start_with?("+++") },
          "deletions" => patch.lines.count { |line| line.start_with?("-") && !line.start_with?("---") } }
      end

      def file_lines(files, more)
        listed = files.first(FILE_LIMIT).map { |file| "  #{file['filename']} (#{file['status']}, +#{file['additions']} -#{file['deletions']})" }
        listed << "  ... more files than these" if more || files.size > FILE_LIMIT
        listed.join("\n")
      end

      def deployment_line(deployment)
        job = deployment["deployable"] || {}
        "#{deployment['created_at']}  #{deployment.dig('environment', 'name') || 'unknown environment'}  #{deployment['ref']}  " \
          "#{deployment['sha'].to_s[0, 12]}  #{deployment['status']}  by #{deployment.dig('user', 'username') || 'unknown'}  " \
          "deployment #{deployment['id']}#{"  job #{job['id']} #{job['web_url']}" if job['id']}"
      end

      # An environment asked for by name, else anything that looks like production, else every environment.
      def scoped_to_environment(deployments, environment)
        named = ->(deployment) { deployment.dig("environment", "name").to_s }
        return deployments.select { |deployment| named.call(deployment).casecmp?(environment) } if environment.present?

        production = deployments.select { |deployment| named.call(deployment).match?(CodeHost::PRODUCTION) }
        production.presence || deployments
      end

      def deployed_text(repo, at, running, previous = nil)
        finished = ->(deployment) { deployment.dig("deployable", "finished_at") || deployment["updated_at"] }
        lines = [
          "Running in #{repo} at #{at.iso8601}: #{running['sha']}",
          "Source: a deployment. #{running.dig('environment', 'name')} deployment #{running['id']} succeeded #{finished.call(running)} " \
            "by #{running.dig('user', 'username') || 'unknown'}, ref #{running['ref']}."
        ]
        if previous
          lines << "Deployed before it: #{previous['sha']}, succeeded #{finished.call(previous)}."
          lines << "What this deployment changed: compare_commits with base #{previous['sha']} and head #{running['sha']}."
        else
          lines << "No earlier successful deployment is recorded, so there is nothing to compare this deployment against."
        end
        lines.join("\n")
      end

      def default_branch_text(gitlab, repo, at)
        branch = gitlab.get(GitlabApi.project(repo))["default_branch"]
        fail! "#{repo} has no default branch, so no commit can be named." if branch.blank?

        head = commit_on_branch_at(gitlab, repo, branch, at)
        fail! "No commit on #{branch} before #{at.iso8601}." unless head

        base = commit_on_branch_at(gitlab, repo, branch, at - NO_DEPLOY_LOOKBACK)
        lines = [
          "Running in #{repo} at #{at.iso8601}: not known. There is no successful deployment before then.",
          "Tip of #{branch} at that time: #{head['id']} (#{head['committed_date']}).",
          "This is a guess from the default branch, not proof it was deployed. Say so when relying on it."
        ]
        lines << if base && base["id"] != head["id"]
          "What reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before: compare_commits with base #{base['id']} and head #{head['id']}."
        else
          "Nothing reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before."
        end
        lines.join("\n")
      end

      def commit_on_branch_at(gitlab, repo, branch, at)
        Array(gitlab.get("#{GitlabApi.project(repo)}/repository/commits", "ref_name" => branch, "until" => at.iso8601, "per_page" => 1)).first
      end

      def comparison_text(gitlab, repo, base, comparison)
        commits = Array(comparison["commits"]).sort_by { |commit| commit["committed_date"].to_s }
        files = Array(comparison["diffs"]).map { |diff| changed_file(diff) }
        head = commits.last&.dig("id") || comparison.dig("commit", "id")
        notes = []
        notes << "GitLab stopped comparing before the end, so some diffs may be missing. The commits are complete." if comparison["compare_timeout"]
        notes << "Base and head are the same, so nothing changed." if comparison["compare_same_ref"]
        [
          "#{commits.size} commits, #{files.size} files changed. Base #{base}, head #{head}.#{" #{notes.join(' ')}" if notes.any?}",
          grouped_files(files),
          dependency_text(files),
          merge_requests_text(gitlab, repo, commits),
          owners_text(files, code_owners(gitlab, repo, head)),
          diffs_text(gitlab, repo, head, files),
          (Telemetry.link_line(link(comparison["web_url"])) if comparison["web_url"].present?)
        ].compact.join("\n\n")
      end

      # Newest commits first, the merge requests that brought them, so a long range still names who to ask.
      def merge_requests_text(gitlab, repo, commits)
        lines = commits.reverse.map do |commit|
          "  #{commit['id'].to_s[0, 12]}  #{commit['authored_date']}  #{commit['author_name']}  #{commit['title']}"
        end
        requests = commits.last(PULL_LOOKUP_LIMIT).reverse.flat_map { |commit| merge_requests_of(gitlab, repo, commit["id"]) }.uniq { |request| request["iid"] }
        text = "Commits, newest first:\n#{lines.join("\n")}"
        if requests.any?
          listed = requests.map do |request|
            approved = approvers(gitlab, repo, request["iid"])
            "  MR !#{request['iid']} #{request['title']} by #{request.dig('author', 'username')}" \
              "#{approved.any? ? ", approved by #{approved.join(', ')}" : ', no approvals'} #{request['web_url']}"
          end
          text += "\n\nMerge requests:\n#{listed.join("\n")}"
        end
        text += "\n(Merge requests looked up for the newest #{PULL_LOOKUP_LIMIT} commits of #{commits.size}.)" if commits.size > PULL_LOOKUP_LIMIT
        text
      end

      def merge_requests_of(gitlab, repo, sha)
        Array(gitlab.get("#{GitlabApi.project(repo)}/repository/commits/#{sha}/merge_requests"))
      rescue GitlabApi::Error
        []
      end

      def code_owners(gitlab, repo, ref)
        CODEOWNERS_PATHS.each do |path|
          return CodeChange::Owners.new(gitlab.text("#{GitlabApi.file(repo, path)}/raw", "ref" => ref || HEAD))
        rescue GitlabApi::NotFound
          next
        end
        nil
      end

      def diffs_text(gitlab, repo, head, files)
        ordered = files.sort_by { |file| CodeChange::KINDS.index(CodeChange.kind_for(file["filename"])) }
        diffs = ordered.map do |file|
          body = shown_patch(file["filename"], file["patch"].presence || "(no text diff, binary or too large for GitLab to show)")
          "#{file['filename']} #{blob_link(gitlab, repo, head, file['filename'])&.url}\n#{body}"
        end
        "Diffs:\n\n#{diffs.join("\n\n")}"
      end

      # GitLab gives each range's lines without numbers, so they are counted from the first line asked for.
      def blame_text(gitlab, repo, path, ref, ranges, from, to)
        line = from
        rendered = ranges.map do |range|
          commit = range["commit"]
          count = Array(range["lines"]).size
          span = "L#{line}-#{[ line + count - 1, to ].min}"
          line += count
          "#{span.ljust(12)} #{commit['id'].to_s[0, 12]} #{commit['committed_date']} #{commit['message'].to_s.lines.first&.strip} (#{commit['author_name']})"
        end
        distinct = ranges.map { |range| range.dig("commit", "id") }.uniq
        requests = distinct.first(BLAME_MERGE_REQUESTS).flat_map { |sha| merge_requests_of(gitlab, repo, sha).first(1) }.uniq { |request| request["iid"] }
        merged = requests.any? ? "\nMerge requests: #{requests.map { |request| "!#{request['iid']} #{Sentence.clean(request['title'])} #{request['web_url']}" }.to_sentence}." : ""
        "#{path}:#{from}-#{to} at #{ref || 'the default branch'}\n#{rendered.join("\n")}\n\n" \
          "Commits touching this range: #{distinct.map { |sha| sha.to_s[0, 12] }.join(', ')}.#{merged} Use commit_lookup or mr_lookup for the full change."
      end
    end
  end
end
