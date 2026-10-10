module Integrations
  module Packs
    # Bitbucket Cloud for the workspaces a connection reads, one, several or every one its token can read (the workspace
    # connect field, a scope). A repository names its workspace, so a call about one reaches only that workspace, and a
    # listing named none lists every workspace. Read with a token through Bitbucket's REST API (2.0, its OpenAPI description at
    # api.bitbucket.org/swagger.json): pull requests, commits, deployments, pipelines and their steps, and files.
    # Bitbucket has no blame in its API, so blame runs git in the run's sandbox, where reading code by search, definition,
    # history and language server happens too (CodeHost::Code). The pipelines tools live in Bitbucket::Pipelines. Every
    # tool only reads but the sandbox's test runner and the ones that run, rerun or stop a pipeline.
    class Bitbucket < NativePack
      # The environment row's credentials, which only this pack reads.
      WORKSPACE = "workspace".freeze
      TOKEN = "token".freeze

      PROVIDER = "Bitbucket".freeze
      PROVIDER_KEY = "bitbucket".freeze
      REPO_PARAM = { "type" => "string", "description" => "Repository as workspace/repository, e.g. acme/checkout" }.freeze
      REPOS_PARAM = { "type" => "array", "items" => { "type" => "string" }, "description" => "Repositories as workspace/repository (optional, every repository this connection can see)" }.freeze

      Code = CodeHost::Code
      include CodeHost
      include Code
      include Pipelines
      include CiConfig

      REPO_FORMAT = %r{\A[\w.\-]+/[\w.\-]+\z}
      WORKSPACE_FORMAT = /\A[\w.\-]+\z/
      SHA_FORMAT = /\A\h{6,40}\z/
      FILE_LIMIT = 30
      MERGED_LIMIT = 10
      MERGED_CANDIDATES = 50
      DEPLOYMENT_LIMIT = 10
      MAX_DEPLOYMENTS = 50
      # Bitbucket's deployments list takes no filter or order, so this many pages are read and ordered here.
      DEPLOYMENT_PAGES = 3
      COMMIT_PAGES = 5
      NO_DEPLOY_LOOKBACK = 24.hours
      PULL_LOOKUP_LIMIT = 25
      BLAME_PULL_REQUESTS = 5
      # Bitbucket's code owners feature reads this one file (support.atlassian.com, set up and use code owners).
      CODEOWNERS_PATH = ".bitbucket/CODEOWNERS".freeze
      MAX_REPOSITORY_PAGES = 10
      MERGED = "MERGED".freeze
      COMPLETED = "COMPLETED".freeze
      SUCCESSFUL = "SUCCESSFUL".freeze
      # Bitbucket documents this name for signing git in with an access token or an API token.
      GIT_USER = "x-token-auth".freeze
      # git blame --porcelain starts each line's header with the commit and its line numbers.
      BLAME_HEADER = /\A(\h{40}) \d+ (\d+)/

      tool :list_repositories,
           description: "List the repositories in this Bitbucket workspace, with each one's main branch and last update",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :pr_lookup,
           description: "Fetch a pull request: title, state, author, who closed it, its branches and merge commit, who approved it, and the changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "id" => { "type" => "integer", "description" => "The pull request's number, as in #42" } }, %w[repo id]),
           read_only: true

      tool :commit_lookup,
           description: "Fetch a commit: message, author, stats, and changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "sha" => { "type" => "string", "description" => "Commit SHA" } }, %w[repo sha]),
           read_only: true

      tool :recent_deployments,
           description: "List a repository's deployments, newest first, each with the environment, the release and commit deployed, " \
                        "the outcome, who ran it and the pipeline that made it",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "deployment_environment" => { "type" => "string", "description" => "Only this environment, by name, e.g. Production (optional)" },
             "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT}, at most #{MAX_DEPLOYMENTS})" }
           }, %w[repo]),
           read_only: true

      tool :merged_pull_requests,
           description: "List pull requests merged into a repository, most recently updated first, optionally only those updated since a " \
                        "given time. Bitbucket keeps no merge time, so a pull request's last update stands for it",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "since" => { "type" => "string", "description" => "Only pull requests updated at or after this time, as ISO 8601 (optional)" }
           }, %w[repo]),
           read_only: true

      tool :running_commit,
           description: "Which commit was running at a given time: the last deployment that succeeded before it, and the one before " \
                        "that to compare against. Without a deployment it falls back to the main branch at that time and says " \
                        "so, since a merge is not proof of a deploy",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "at" => { "type" => "string", "description" => "The time, as ISO 8601, usually when the incident started" },
             "deployment_environment" => { "type" => "string", "description" => "The environment, e.g. Production (optional, production when there is one)" }
           }, %w[repo at]),
           read_only: true

      tool :compare_commits,
           description: "What changed between two commits: the commits and pull requests with their authors and approvers, " \
                        "the changed files grouped by kind with migrations, config and dependencies first, dependency bumps " \
                        "in plain words, who owns the changed files, and every diff",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "base" => { "type" => "string", "description" => "The earlier commit SHA, branch or tag" },
             "head" => { "type" => "string", "description" => "The later commit SHA, branch or tag" }
           }, %w[repo base head]),
           read_only: true

      tool :fetch_file,
           description: "Read a file from the repository at a given commit, optionally sliced to a line range with surrounding context",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "path" => { "type" => "string", "description" => "File path within the repository" },
             "ref" => Code::REF,
             "start_line" => { "type" => "integer", "description" => "First line of interest (optional, the slice includes context around it)" },
             "end_line" => { "type" => "integer", "description" => "Last line of interest (optional)" }
           }, %w[repo path]),
           read_only: true

      tool :blame,
           description: "Attribute a line range, as it stood at a given commit, to the commits and pull requests that last touched it. " \
                        "Read with git in the code sandbox, since Bitbucket's API has no blame",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "path" => { "type" => "string", "description" => "File path within the repository" },
             "ref" => Code::REF,
             "start_line" => { "type" => "integer", "description" => "First line of the range" },
             "end_line" => { "type" => "integer", "description" => "Last line of the range" }
           }, %w[repo path start_line end_line]),
           read_only: true

      tool :api_read,
           description: "Anything else Bitbucket's REST API reads that the other Bitbucket tools do not cover, such as a repository's " \
                        "deployment environments, branch restrictions, branching model, members and permissions, or a workspace's " \
                        "projects. A GET to a path of Bitbucket Cloud's REST API (#{BitbucketApi::API_ROOT}), written after /2.0, " \
                        "such as /repositories/<workspace>/<repo>/environments. A list answers one page: pass pagelen, at most 100, " \
                        "and page 2, 3 and on while the answer names a next page. Only reads, so it never changes anything. " \
                        "Pipeline and deployment variables and webhooks come back as their names",
           params_schema: ApiReads.path_schema("/repositories/<workspace>/<repo>/environments"),
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN, label: "Token", secret: true, placeholder: "ATATT...",
                              hint: "An API token, or a workspace access token, that can read repositories, pull requests and pipelines " \
                                    "(read:repository:bitbucket, read:pullrequest:bitbucket and read:pipeline:bitbucket). Listing its workspaces to choose " \
                                    "from, or reading every one, needs read:workspace:bitbucket. Running, rerunning or stopping a " \
                                    "pipeline also needs write:pipeline:bitbucket. Following changes live " \
                                    "needs a workspace owner's token with read:webhook:bitbucket, write:webhook:bitbucket and delete:webhook:bitbucket.")
        ]
      end

      # Lists a repository of each workspace chosen (the workspace connect field) with the token, or lists the workspaces
      # for every one it can read, so a wrong workspace or token is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[TOKEN].to_s.strip
        workspaces = Array(fields.to_h[WORKSPACE]).map { |each| each.to_s.strip }.compact_blank
        return "Paste a token." if token.empty?
        return "Choose at least one workspace, or all the token can read." if workspaces.empty?
        if workspaces == [ IntegrationProvider::ConnectField::ALL ]
          return scope_options(values).empty? ? "This token can read no Bitbucket workspaces." : nil
        end

        workspace = workspaces.find { |each| !each.match?(WORKSPACE_FORMAT) }
        return "Enter each workspace's id, such as acme." if workspace

        workspaces.each do |each|
          workspace = each
          BitbucketApi.new(token).get("/repositories/#{Http.segment(each)}", "pagelen" => 1)
        end
        nil
      rescue NativePack::Error => error
        error.message
      rescue BitbucketApi::Refused => error
        Sentence.join("Bitbucket refused this token", error, after: "Check it can read repositories in #{workspace}")
      rescue BitbucketApi::NotFound
        "Bitbucket has no workspace #{workspace} that this token can see."
      rescue BitbucketApi::Error => error
        Sentence.join("Bitbucket could not be reached with this token", error)
      end

      # The workspaces the token can read, by their ids (GET /2.0/user/workspaces, "List workspaces for the current user",
      # which answers each workspace's slug and uuid but no name, in Bitbucket's OpenAPI description at
      # dac-static.atlassian.com/cloud/bitbucket/swagger.v3.json). It needs read:workspace:bitbucket. The older
      # GET /2.0/workspaces no longer answers (community.developer.atlassian.com/t/99972).
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[TOKEN].to_s.strip
        raise NativePack::Error, "Paste a token first." if token.empty?

        listed, = BitbucketApi.new(token).list("/user/workspaces", {}, pages: MAX_REPOSITORY_PAGES)
        listed.filter_map { |access| access.dig("workspace", "slug").presence }.uniq.map { |slug| IntegrationProvider::ConnectOption.new(value: slug, label: slug) }
      rescue BitbucketApi::Refused => error
        raise NativePack::Error, Sentence.join("Bitbucket did not list this token's workspaces", error, after: "Listing them needs read:workspace:bitbucket")
      rescue BitbucketApi::Error => error
        raise NativePack::Error, Sentence.join("Bitbucket did not list this token's workspaces", error)
      end

      # A tool names the repository it acts on, which lives in one workspace.
      def self.scope_references(arguments) = [ arguments["repo"], *Array(arguments["repos"]) ]

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(TOKEN, values[TOKEN].to_s.strip)
      end

      def list_repositories(environment_row:, arguments:)
        if every_scope?(environment_row)
          return ConnectionSettings.of(environment_row).scopes.map { |each| "Workspace #{each}:\n#{scoped(each).list_repositories(environment_row: environment_row, arguments: arguments)}" }.join("\n\n")
        end

        workspace = workspace_of(environment_row)
        repositories, more = api(environment_row).list("/repositories/#{Http.segment(workspace)}", "sort" => "-updated_on")
        return "Workspace #{workspace} has no repositories this token can see." if repositories.empty?

        listed = repositories.map do |repository|
          "#{repository['full_name']}  main branch #{repository.dig('mainbranch', 'name') || 'none'}  last update #{repository['updated_on']}  " \
            "#{repository.dig('links', 'html', 'href')}"
        end
        "#{listed.join("\n")}#{"\nMore repositories than these. Name one to read it." if more}"
      end

      def pr_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        id = Integer(arguments["id"].to_s, exception: false)
        fail! "id must be the pull request's number" unless id&.positive?

        bitbucket = api(environment_row)
        request = bitbucket.get("#{BitbucketApi.repository(repo)}/pullrequests/#{id}")
        files, more = bitbucket.list("#{BitbucketApi.repository(repo)}/pullrequests/#{id}/diffstat")
        Telemetry.result(<<~TEXT, link: link(request.dig("links", "html", "href")))
          PR ##{request['id']}: #{request['title']}
          State: #{pull_state(request)}
          Author: #{request.dig('author', 'display_name')}
          Branch: #{request.dig('source', 'branch', 'name')} -> #{request.dig('destination', 'branch', 'name')}
          Approved by: #{approvers(request).presence&.join(', ') || 'nobody'}
          Changes: #{files.size}#{'+' if more} files

          #{file_lines(files.map { |stat| changed_file(stat) }, more)}
          #{request['description'].presence || '(no description)'}
        TEXT
      end

      def commit_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        sha = arguments["sha"].to_s
        fail! "sha must be a commit SHA" unless sha.match?(SHA_FORMAT)

        bitbucket = api(environment_row)
        commit = bitbucket.get("#{BitbucketApi.repository(repo)}/commit/#{sha}")
        files, more = bitbucket.list("#{BitbucketApi.repository(repo)}/diffstat/#{sha}")
        changed = files.map { |stat| changed_file(stat) }
        Telemetry.result(<<~TEXT, link: link(commit.dig("links", "html", "href")))
          Commit #{commit['hash']}
          Author: #{commit.dig('author', 'raw')} at #{commit['date']}
          Changes: +#{changed.sum { |file| file['additions'] }} -#{changed.sum { |file| file['deletions'] }}

          #{commit['message']}

          #{file_lines(changed, more)}
        TEXT
      end

      def recent_deployments(environment_row:, arguments:)
        repo = repo_argument(arguments)
        limit = whole_number_argument(arguments, "limit", DEPLOYMENT_LIMIT, MAX_DEPLOYMENTS)
        named = arguments["deployment_environment"].to_s
        deployments = deployments_of(api(environment_row), repo)
        deployments = deployments.select { |deployment| deployment["environment_name"].casecmp?(named) } if named.present?
        return "No deployments recorded for #{repo}#{" in #{named}" if named.present?}." if deployments.empty?

        # Each line links the pipeline that made the release, the address Bitbucket gives it. The deployments list has none.
        deployments.first(limit).map { |deployment| deployment_line(deployment) }.join("\n")
      end

      def merged_pull_requests(environment_row:, arguments:)
        repo = repo_argument(arguments)
        since = since_argument(arguments)
        query = { "state" => MERGED, "sort" => "-updated_on", "pagelen" => MERGED_CANDIDATES, "q" => (%(updated_on >= #{since.utc.iso8601}) if since) }
        merged = Array(api(environment_row).get("#{BitbucketApi.repository(repo)}/pullrequests", query)["values"]).first(MERGED_LIMIT)
        return "No pull requests merged#{since ? " and updated since #{since.iso8601}" : ''} in #{repo}." if merged.empty?

        merged.map do |request|
          "PR ##{request['id']}  #{request['title']}  merged, last updated #{request['updated_on']}, by #{request.dig('closed_by', 'display_name') || 'unknown'} " \
            "into #{request.dig('destination', 'branch', 'name')}  #{request.dig('links', 'html', 'href')}"
        end.join("\n")
      end

      def running_commit(environment_row:, arguments:)
        repo = repo_argument(arguments)
        at = time_argument(arguments, "at")
        bitbucket = api(environment_row)
        succeeded = deployments_of(bitbucket, repo).select do |deployment|
          deployment["finished"] && deployment["finished"] <= at && deployment.dig("state", "status", "name") == SUCCESSFUL
        end
        deployed = scoped_to_environment(succeeded, arguments["deployment_environment"].to_s).first(2)
        return deployed_text(repo, at, *deployed) if deployed.any?

        main_branch_text(bitbucket, repo, at)
      end

      def compare_commits(environment_row:, arguments:)
        repo = repo_argument(arguments)
        base = ref_argument(arguments, "base", required: true)
        head = ref_argument(arguments, "head", required: true)
        bitbucket = api(environment_row)
        # Bitbucket writes a range the other way round from git diff, so head..base is what changed from base to head.
        spec = "#{head}..#{base}"
        stats, more = bitbucket.list("#{BitbucketApi.repository(repo)}/diffstat/#{Http.segment(spec)}", {}, pages: 3)
        patches = patches_by_file(bitbucket.text("#{BitbucketApi.repository(repo)}/diff/#{Http.segment(spec)}"))
        files = stats.map { |stat| changed_file(stat, patches) }
        commits, more_commits = bitbucket.list("#{BitbucketApi.repository(repo)}/commits", { "include" => head, "exclude" => base }, pages: 3)
        comparison_text(bitbucket, repo, base, head, commits, files, more || more_commits)
      end

      def fetch_file(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        ref = ref_argument(arguments)
        bitbucket = api(environment_row)
        commit = commit_of(bitbucket, repo, ref)
        lines = read_file(bitbucket, repo, commit, path, ref).lines
        from, to = slice_range(arguments, lines.size)
        Telemetry.result("#{path}:#{from}-#{to} (of #{lines.size} lines) at #{ref || 'the main branch'}, commit #{commit[0, 12]}\n" \
                         "#{lines.empty? ? '(empty file)' : numbered(lines, from, to)}", link: commit_link(repo, commit))
      end

      def blame(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        from, to = line_range!(arguments)
        ref = ref_argument(arguments)
        result = code(environment_row).exec(repo, ref: ref, where: Sandboxes::Client::IN_GIT,
                                                  argv: [ "blame", "--porcelain", "-L", "#{from},#{to}", Sandboxes::Client::COMMIT, "--", path ])
        fail! "No blame for '#{path}' at #{ref || 'the main branch'}: #{result['stderr'].to_s.strip.lines.last}" unless result["exit_code"].to_i.zero?

        ranges = blame_ranges(result["stdout"].to_s)
        fail! "No blame for '#{path}' at #{ref || 'the main branch'}." if ranges.empty?

        Telemetry.result(blame_text(api(environment_row), repo, path, ref, ranges, from, to), link: commit_link(repo, result["commit"]))
      end

      # The workspace's repositories, and the infrastructure defined as code in them, so the map knows what each one
      # manages. Read once a day, and on Sync now.
      EVERY = 1.day

      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: [ ResourceMap::KIND_REPOSITORY ]) { |pack| pack.map_of_workspace(environment_row) }
      end

      def map_of_workspace(environment_row)
        bitbucket = api(environment_row)
        workspace = workspace_of(environment_row)
        listed, more = bitbucket.list("/repositories/#{Http.segment(workspace)}", {}, pages: MAX_REPOSITORY_PAGES)
        listing = more ? [ ResourceMap::Gap.new(text: "Only the first #{listed.size} repositories were listed.", kinds: [ ResourceMap::KIND_REPOSITORY ]) ] : []
        repositories_snapshot(bitbucket, workspace, listed, gaps: listing)
      end

      # Only the repository a change named, read again as the sweep reads it, with its infrastructure files, or a branch a
      # push named, whose repository is read again only when it is the main branch, since a push says nothing of which
      # branch is main. Gone only when Bitbucket answers not found for the repository. nil for a scope Bitbucket cannot
      # narrow to, which a sweep reads.
      def map_refresh(environment_row, scope)
        return unless scope.external_id

        if every_scope?(environment_row)
          # A repository or branch names its workspace first, and a change in one the connection does not read changes nothing here.
          workspace = scope.external_id.split("/").first
          return ConnectionSettings.of(environment_row).scopes.include?(workspace) ? scoped(workspace).map_refresh(environment_row, scope) : ResourceMap::Snapshot.new(resources: [])
        end

        case scope.kind
        when nil, ResourceMap::KIND_REPOSITORY then refreshed_repository(environment_row, scope.external_id)
        when ResourceMap::KIND_BRANCH then pushed_branch(environment_row, scope.external_id)
        end
      end

      def refreshed_repository(environment_row, name)
        return unless name.match?(REPO_FORMAT)

        bitbucket = api(environment_row)
        workspace = workspace_of(environment_row)
        repository = begin
          bitbucket.get(BitbucketApi.repository(name))
        rescue BitbucketApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, workspace, ResourceMap::KIND_REPOSITORY, name ] ])
        end
        repositories_snapshot(bitbucket, workspace, [ repository ])
      end
      private :refreshed_repository

      # A branch is named as workspace/repository/branch, and a branch's own name may hold slashes.
      def pushed_branch(environment_row, name)
        workspace_slug, slug, branch = name.split("/", 3)
        return unless branch.present?

        bitbucket = api(environment_row)
        repository = begin
          bitbucket.get(BitbucketApi.repository("#{workspace_slug}/#{slug}"))
        rescue BitbucketApi::NotFound
          return ResourceMap::Snapshot.new(resources: [])
        end
        return ResourceMap::Snapshot.new(resources: []) unless repository.dig("mainbranch", "name") == branch

        repositories_snapshot(bitbucket, workspace_of(environment_row), [ repository ])
      end
      private :pushed_branch

      # The repositories as the map has them, with the infrastructure defined as code in them. A file left unread holds
      # back a suggestion, never a resource.
      def repositories_snapshot(bitbucket, workspace, listed, gaps: [])
        infrastructure = Infrastructure.new(bitbucket)
        files = infrastructure.files(listed.map { |repository| repository_of(repository) })
        found = listed.map do |repository|
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: workspace, kind: ResourceMap::KIND_REPOSITORY, external_id: repository["full_name"],
                                 name: repository["full_name"], url: repository.dig("links", "html", "href"),
                                 details: { "branch" => repository.dig("mainbranch", "name") }.compact)
        end
        unread_files = infrastructure.gaps.map { |text| ResourceMap::Gap.new(text: text, kinds: []) }
        ResourceMap::Snapshot.new(resources: found, gaps: [ *gaps, *unread_files ], code_files: files, code_read: infrastructure.read_in_full)
      end
      private :repositories_snapshot

      # Paths that name a workspace in their second segment, which is how a read is kept to the ones the connection reads.
      IN_WORKSPACE = %w[repositories workspaces snippets].freeze

      # A path names a workspace the connection reads, unless the connection reads every workspace its token can.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Bitbucket.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        settings = ConnectionSettings.of(environment_row)
        kind, workspace, slug = path.delete_prefix("/").split("/", 4)
        named = workspace if IN_WORKSPACE.include?(kind)
        if named.nil? && !settings.all_scopes?
          fail_policy!("This connection reads the workspaces #{settings.chosen_scopes.to_sentence} only, so a read names one, such as " \
                       "/repositories/#{settings.chosen_scopes.first}/<repo>.")
        end
        outside = ApiReads.outside_scopes(settings, [ named ], "workspaces")
        fail_policy!(outside) if outside

        answer = api(environment_row).read(path, query)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::Bitbucket.secret?(path))
        page = (answer.dig("links", "html", "href") if answer.is_a?(Hash) && answer["links"].is_a?(Hash) && answer["links"]["html"].is_a?(Hash))
        page ||= [ @site, named, slug ].join("/") if kind == IN_WORKSPACE.first && named && slug.present? && @site.present?
        Telemetry.result(text, link: link(page))
      rescue BitbucketApi::Refused => error
        fail! Sentence.join("Bitbucket refused this read", error, after: "The token's scopes do not reach it")
      end

      # Lists a repository of each workspace the connection reaches, so one the token can no longer read is said on the
      # connection.
      def check_health!(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |workspace| api(environment_row).get("/repositories/#{Http.segment(workspace)}", "pagelen" => 1) }
      rescue BitbucketApi::Error => error
        fail! error.message
      end

      private

      # Every tool reaches the API first, so the site its links open is known by the time it links.
      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        @site = settings.site
        token = settings.credential(TOKEN)
        fail! "This environment has no Bitbucket token. Reconnect it on the Integrations page." if token.blank?

        BitbucketApi.new(token)
      end

      def workspace_of(environment_row) = scope!(environment_row)

      def visible_repositories(environment_row)
        return ConnectionSettings.of(environment_row).scopes.flat_map { |each| scoped(each).send(:visible_repositories, environment_row) } if every_scope?(environment_row)

        api(environment_row).list("/repositories/#{Http.segment(workspace_of(environment_row))}", "sort" => "-updated_on").first.map { |repository| repository["full_name"] }
      end

      # The sandbox fetches from Bitbucket's site, signing in as Bitbucket documents for a token, and never follows a redirect.
      def code_remote(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(TOKEN)
        fail! "This environment has no Bitbucket token. Reconnect it on the Integrations page." if token.blank?

        CodeReading::Remote.new(host: URI.parse(settings.site).host, root: settings.site, user: GIT_USER, token: -> { token },
                                options: [ "http.followRedirects=false" ])
      end

      def repo_argument(arguments)
        repo = arguments["repo"].to_s
        fail! "repo must be workspace/repository, such as acme/checkout" unless repo.match?(REPO_FORMAT) && !repo.include?("..")

        repo
      end

      # A repository in the shape the infrastructure reader takes. Bitbucket has no archived repositories.
      def repository_of(repository)
        { "full_name" => repository["full_name"], "default_branch" => repository.dig("mainbranch", "name"), "url" => repository.dig("links", "html", "href"),
          "size" => repository["size"].to_i, "archived" => false, "fork" => repository["parent"].present? }
      end

      def link(url) = url.present? ? Telemetry::Link.new(provider: PROVIDER, url: url) : nil

      # Bitbucket's API gives a file, a pipeline and a step no page of their own, and its docs publish none, so a result
      # about one links the commit it was read at or built, at the address the API gives a commit (links.html.href, such
      # as bitbucket.org/<workspace>/<repository>/commits/<hash> in its examples).
      def commit_link(repo, commit) = link([ @site, repo, "commits", commit ].join("/"))

      # The commit a ref names, so a file is read and linked at a commit rather than a moving branch.
      def commit_of(bitbucket, repo, ref)
        revision = ref || bitbucket.get(BitbucketApi.repository(repo)).dig("mainbranch", "name")
        fail! "#{repo} has no main branch yet, so name a ref." if revision.blank?

        Array(bitbucket.get("#{BitbucketApi.repository(repo)}/commits/#{Http.segment(revision)}", "pagelen" => 1)["values"]).first&.dig("hash") ||
          fail!("No commit at #{revision} in #{repo}.")
      rescue BitbucketApi::NotFound
        fail! "No commit at #{revision} in #{repo}."
      end

      def read_file(bitbucket, repo, commit, path, ref)
        bitbucket.text("#{BitbucketApi.repository(repo)}/src/#{commit}/#{BitbucketApi.path(path)}")
      rescue BitbucketApi::NotFound
        fail! "No file at '#{path}' #{ref ? "at #{ref}" : 'on the main branch'}."
      end

      def pull_state(request)
        state = request["state"].to_s.downcase
        return state unless request["state"] == MERGED

        "merged as #{request.dig('merge_commit', 'hash') || 'unknown'} by #{request.dig('closed_by', 'display_name') || 'unknown'}, last updated #{request['updated_on']}"
      end

      # Bitbucket names a pull request's participants, and whether each approved, only when it is read on its own.
      def approvers(request)
        Array(request["participants"]).select { |participant| participant["approved"] }.filter_map { |participant| participant.dig("user", "display_name") }
      end

      # A diffstat entry in the shape the change summaries read: filename, status, additions, deletions and patch.
      def changed_file(stat, patches = {})
        name = stat.dig("new", "path") || stat.dig("old", "path")
        { "filename" => name, "status" => stat["status"], "additions" => stat["lines_added"].to_i, "deletions" => stat["lines_removed"].to_i,
          "patch" => patches[name] }
      end

      # One unified diff split by file, keyed by the file's new path.
      def patches_by_file(diff)
        diff.split(/^(?=diff --git )/).each_with_object({}) do |chunk, patches|
          name = chunk[%r{\Adiff --git a/.+? b/(.+)$}, 1]
          patches[name] = chunk if name
        end
      end

      def file_lines(files, more)
        listed = files.first(FILE_LIMIT).map { |file| "  #{file['filename']} (#{file['status']}, +#{file['additions']} -#{file['deletions']})" }
        listed << "  ... more files than these" if more || files.size > FILE_LIMIT
        listed.join("\n")
      end

      # Deployments newest first, each with its environment's name and when it finished, since Bitbucket's list takes no
      # order and names the environment only by its id.
      def deployments_of(bitbucket, repo)
        environments = bitbucket.list("#{BitbucketApi.repository(repo)}/environments").first.to_h { |environment| [ environment["uuid"], environment["name"] ] }
        bitbucket.list("#{BitbucketApi.repository(repo)}/deployments", {}, pages: DEPLOYMENT_PAGES).first.map do |deployment|
          state = deployment["state"] || {}
          deployment.merge("environment_name" => environments[deployment.dig("environment", "uuid")] || deployment.dig("environment", "name").to_s,
                           "finished" => Telemetry.parse_time(state["completion_date"]), "started" => Telemetry.parse_time(state["start_date"]))
        end.sort_by { |deployment| deployment["finished"] || deployment["started"] || Time.zone.at(0) }.reverse
      end

      def deployment_line(deployment)
        state = deployment["state"] || {}
        outcome = state.dig("status", "name") || state["name"]
        "#{state['completion_date'] || state['start_date'] || 'not started'}  #{deployment['environment_name'].presence || 'unknown environment'}  " \
          "#{deployment.dig('release', 'name')}  #{deployment.dig('release', 'commit', 'hash').to_s[0, 12]}  #{outcome.to_s.downcase}  " \
          "by #{state.dig('deployer', 'display_name') || 'unknown'}  deployment #{deployment['uuid']}  #{deployment.dig('release', 'url')}"
      end

      def scoped_to_environment(deployments, environment)
        return deployments.select { |deployment| deployment["environment_name"].casecmp?(environment) } if environment.present?

        production = deployments.select { |deployment| deployment["environment_name"].match?(PRODUCTION) }
        production.presence || deployments
      end

      def deployed_text(repo, at, running, previous = nil)
        sha = ->(deployment) { deployment.dig("release", "commit", "hash") }
        lines = [
          "Running in #{repo} at #{at.iso8601}: #{sha.call(running)}",
          "Source: a deployment. #{running['environment_name']} deployment of #{running.dig('release', 'name')} succeeded " \
            "#{running['finished'].utc.iso8601} by #{running.dig('state', 'deployer', 'display_name') || 'unknown'}."
        ]
        if previous
          lines << "Deployed before it: #{sha.call(previous)}, succeeded #{previous['finished'].utc.iso8601}."
          lines << "What this deployment changed: compare_commits with base #{sha.call(previous)} and head #{sha.call(running)}."
        else
          lines << "No earlier successful deployment is recorded, so there is nothing to compare this deployment against."
        end
        lines.join("\n")
      end

      # The main branch's history is read newest first, a page at a time, until a commit from before the time.
      def main_branch_text(bitbucket, repo, at)
        branch = bitbucket.get(BitbucketApi.repository(repo)).dig("mainbranch", "name")
        fail! "#{repo} has no main branch, so no commit can be named." if branch.blank?

        commits = bitbucket.list("#{BitbucketApi.repository(repo)}/commits/#{Http.segment(branch)}", {}, pages: COMMIT_PAGES).first
        before = ->(time) { commits.find { |commit| Telemetry.parse_time(commit["date"])&.<=(time) } }
        head = before.call(at)
        fail! "No commit on #{branch} before #{at.iso8601} among its newest #{commits.size}." unless head

        base = before.call(at - NO_DEPLOY_LOOKBACK)
        lines = [
          "Running in #{repo} at #{at.iso8601}: not known. There is no successful deployment before then.",
          "Tip of #{branch} at that time: #{head['hash']} (#{head['date']}).",
          "This is a guess from the main branch, not proof it was deployed. Say so when relying on it."
        ]
        lines << if base && base["hash"] != head["hash"]
          "What reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before: compare_commits with base #{base['hash']} and head #{head['hash']}."
        else
          "Nothing reached #{branch} in the #{NO_DEPLOY_LOOKBACK.inspect} before."
        end
        lines.join("\n")
      end

      def comparison_text(bitbucket, repo, base, head, commits, files, more)
        newest = commits.first&.dig("hash") || head
        [
          "#{commits.size} commits, #{files.size} files changed. Base #{base}, head #{newest}.#{' Bitbucket listed more than these, so some are missing.' if more}",
          grouped_files(files),
          dependency_text(files),
          pull_requests_text(bitbucket, repo, commits),
          owners_text(files, code_owners(bitbucket, repo, newest)),
          diffs_text(repo, newest, files)
        ].compact.join("\n\n")
      end

      # Bitbucket lists commits newest first. The pull requests that brought the newest ones name who to ask.
      def pull_requests_text(bitbucket, repo, commits)
        lines = commits.map { |commit| "  #{commit['hash'].to_s[0, 12]}  #{commit['date']}  #{commit.dig('author', 'raw')}  #{commit['message'].to_s.lines.first&.strip}" }
        requests = commits.first(PULL_LOOKUP_LIMIT).flat_map { |commit| pull_requests_of(bitbucket, repo, commit["hash"]) }.uniq { |request| request["id"] }
        text = "Commits, newest first:\n#{lines.join("\n")}"
        if requests.any?
          listed = requests.map do |request|
            approved = approvers(full_pull_request(bitbucket, repo, request["id"]))
            "  PR ##{request['id']} #{request['title']} by #{request.dig('author', 'display_name')}" \
              "#{approved.any? ? ", approved by #{approved.join(', ')}" : ', no approvals'} #{request.dig('links', 'html', 'href')}"
          end
          text += "\n\nPull requests:\n#{listed.join("\n")}"
        end
        text += "\n(Pull requests looked up for the newest #{PULL_LOOKUP_LIMIT} commits of #{commits.size}.)" if commits.size > PULL_LOOKUP_LIMIT
        text
      end

      # Bitbucket answers this only once its pull request links are indexed for the repository, so nothing is no answer.
      def pull_requests_of(bitbucket, repo, sha)
        Array(bitbucket.get("#{BitbucketApi.repository(repo)}/commit/#{sha}/pullrequests")["values"])
      rescue BitbucketApi::Error
        []
      end

      def full_pull_request(bitbucket, repo, id)
        bitbucket.get("#{BitbucketApi.repository(repo)}/pullrequests/#{id}")
      rescue BitbucketApi::Error
        {}
      end

      def code_owners(bitbucket, repo, commit)
        CodeChange::Owners.new(bitbucket.text("#{BitbucketApi.repository(repo)}/src/#{commit}/#{CODEOWNERS_PATH}"))
      rescue BitbucketApi::NotFound
        nil
      end

      def diffs_text(repo, head, files)
        ordered = files.sort_by { |file| CodeChange::KINDS.index(CodeChange.kind_for(file["filename"])) }
        diffs = ordered.map do |file|
          body = shown_patch(file["filename"], file["patch"].presence || "(no text diff, binary or too large for Bitbucket to show)")
          "#{file['filename']}\n#{body}"
        end
        "Diffs, at #{commit_link(repo, head).url}:\n\n#{diffs.join("\n\n")}"
      end

      # git blame --porcelain names a commit's author and summary the first time the commit appears, then only its hash.
      def blame_ranges(porcelain)
        commits = {}
        ranges = []
        current = nil
        porcelain.each_line do |line|
          if (header = line.match(BLAME_HEADER))
            current = commits[header[1]] ||= { "id" => header[1] }
            number = header[2].to_i
            last = ranges.last
            if last && last[:commit] == current && last[:to] == number - 1
              last[:to] = number
            else
              ranges << { commit: current, from: number, to: number }
            end
          elsif current
            key, value = line.chomp.split(" ", 2)
            current["author"] = value if key == "author"
            current["time"] = Time.zone.at(value.to_i).utc.iso8601 if key == "author-time"
            current["summary"] = value if key == "summary"
          end
        end
        ranges
      end

      def blame_text(bitbucket, repo, path, ref, ranges, from, to)
        rendered = ranges.map do |range|
          commit = range[:commit]
          "#{"L#{range[:from]}-#{range[:to]}".ljust(12)} #{commit['id'][0, 12]} #{commit['time']} #{commit['summary']} (#{commit['author']})"
        end
        distinct = ranges.map { |range| range[:commit]["id"] }.uniq
        requests = distinct.first(BLAME_PULL_REQUESTS).flat_map { |sha| pull_requests_of(bitbucket, repo, sha).first(1) }.uniq { |request| request["id"] }
        merged = requests.any? ? "\nPull requests: #{requests.map { |request| "##{request['id']} #{request['title']} #{request.dig('links', 'html', 'href')}" }.join(', ')}." : ""
        "#{path}:#{from}-#{to} at #{ref || 'the main branch'}\n#{rendered.join("\n")}\n\n" \
          "Commits touching this range: #{distinct.map { |sha| sha[0, 12] }.join(', ')}.#{merged} Use commit_lookup or pr_lookup for the full change."
      end
    end
  end
end
