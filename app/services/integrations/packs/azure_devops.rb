module Integrations
  module Packs
    # Azure DevOps Services for one organization (the organization connect field) and the projects a connection reads,
    # one, several or every one its token can read (the project connect field, a scope). A repository is named by its
    # project and name, so a call about one reaches that project. Read with a personal access token through Azure
    # DevOps' REST API (7.1, learn.microsoft.com/rest/api/azure/devops): Azure Repos pull requests, commits and files,
    # Azure Pipelines runs with their stages and jobs, the deployments environments record, and classic releases. Azure
    # DevOps has no blame in its API, and its diffs list changed files without their lines, so blame and a comparison's
    # diffs run git in the run's sandbox, where reading code by search, definition, history and language server happens
    # too (CodeHost::Code). The pipelines tools live in AzureDevops::Pipelines and the deployments in
    # AzureDevops::Deployments. Every tool only reads but the sandbox's test runner and the ones that run, retry or
    # cancel a pipeline run, answer an approval or deploy an earlier deployment again.
    class AzureDevops < NativePack
      # The environment row's credential and connect fields, which only this pack reads.
      ORGANIZATION = "organization".freeze
      PROJECT = "project".freeze
      TOKEN = "token".freeze

      PROVIDER = "Azure DevOps".freeze
      PROVIDER_KEY = "azure_devops".freeze
      REPO_PARAM = { "type" => "string", "description" => "Repository as project/repository, e.g. Shop/checkout" }.freeze
      REPOS_PARAM = { "type" => "array", "items" => { "type" => "string" }, "description" => "Repositories as project/repository (optional, every repository this connection can see)" }.freeze

      Code = CodeHost::Code
      include CodeHost
      include Code
      include Pipelines
      include Deployments
      include CiConfig

      # A project or repository name holds no slash, and may hold spaces.
      NAME = %r{[^/\\\0[:cntrl:]]+}
      REPO_FORMAT = %r{\A#{NAME}/#{NAME}\z}
      SHA_FORMAT = /\A\h{40}\z/
      FILE_LIMIT = 30
      MERGED_LIMIT = 10
      MERGED_CANDIDATES = 50
      PULL_LOOKUP_LIMIT = 25
      BLAME_PULL_REQUESTS = 5
      MAX_PROJECT_PAGES = 10
      MAX_DEFINITION_PAGES = 10
      # A pull request's changes are listed this many to a page (Pull Request Iteration Changes - Get, $top at most 2000).
      CHANGES_PAGE = 2000
      FLAG_CHANGE_PAGES = 10
      COMPARE_CHANGES = 1000
      HEADS = "refs/heads/".freeze
      TAGS = "refs/tags/".freeze
      COMPLETED = "completed".freeze
      # A reviewer's vote (GitPullRequest, IdentityRefWithVote.vote): 10 approved, 5 approved with suggestions.
      APPROVED_VOTES = [ 10, 5 ].freeze
      # Azure Repos' type for its own Git repositories in a build's repository (build.complete's sample, TfsGit).
      AZURE_REPOS = "TfsGit".freeze
      # Azure DevOps reads only the token from a Basic sign in, as it does for the REST API, so git signs in under any name.
      GIT_USER = "firefight".freeze
      # git blame --porcelain starts each line's header with the commit and its line numbers.
      BLAME_HEADER = /\A(\h{40}) \d+ (\d+)/
      GIT_FILE = %r{\Adiff --git a/(.+?) b/(.+)\z}
      # A personal access token's scopes, as Azure DevOps names them on the token page (Authorize access with OAuth, scopes).
      SCOPES_WORDS = "Code (Read), Build (Read), Release (Read), Environment (Read & manage), Project and Team (Read)".freeze

      tool :list_repositories,
           summary: "Lists the Azure Repos repositories this connection can see.",
           description: "List the Git repositories in the projects this Azure DevOps connection reads, with each one's default branch and size",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :pr_lookup,
           summary: "Shows a pull request with its author, reviewers, branches and changed files.",
           description: "Fetch a pull request: title, status, author, who completed it and when, its branches and merge commit, how each " \
                        "reviewer voted, and the changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "id" => { "type" => "integer", "description" => "The pull request's number, as in !42" } }, %w[repo id]),
           read_only: true

      tool :commit_lookup,
           summary: "Shows a commit's message, author and changed files.",
           description: "Fetch a commit: message, author, and changed files",
           params_schema: Code.object_schema({ "repo" => REPO_PARAM, "sha" => { "type" => "string", "description" => COMMIT_REFERENCE } }, %w[repo sha]),
           read_only: true

      tool :merged_pull_requests,
           summary: "Lists pull requests recently completed into a repository.",
           description: "List pull requests completed into a repository, newest first, optionally only those completed since a given time",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "since" => { "type" => "string", "description" => "Only pull requests completed at or after this time, as ISO 8601 (optional)" }
           }, %w[repo]),
           read_only: true

      tool :compare_commits,
           summary: "Compares two commits and shows the pull requests, files and diffs between them.",
           description: "What changed between two commits: the commits and the pull requests that brought them with their approvers, " \
                        "the changed files grouped by kind with migrations, config and dependencies first, dependency bumps in plain " \
                        "words, and every diff",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "base" => { "type" => "string", "description" => "The earlier commit SHA, branch or tag" },
             "head" => { "type" => "string", "description" => "The later commit SHA, branch or tag" }
           }, %w[repo base head]),
           read_only: true

      tool :fetch_file,
           summary: "Shows a file from a repository at a given commit.",
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
           summary: "Shows which commits and pull requests last changed some lines of a file.",
           description: "Attribute a line range, as it stood at a given commit, to the commits and pull requests that last touched it",
           params_schema: Code.object_schema({
             "repo" => REPO_PARAM,
             "path" => { "type" => "string", "description" => "File path within the repository" },
             "ref" => Code::REF,
             "start_line" => { "type" => "integer", "description" => "First line of the range" },
             "end_line" => { "type" => "integer", "description" => "Last line of the range" }
           }, %w[repo path start_line end_line]),
           read_only: true

      tool :api_read,
           summary: "Reads other Azure DevOps data, such as branch policies, service connections and agents.",
           description: "Anything else Azure DevOps' REST API reads that the other Azure DevOps tools do not cover, such as a branch's " \
                        "policies, a project's service connections, variable groups, agent pools, test runs or work items. A GET to a " \
                        "path of the REST API, written after the organization as the reference the azure_devops_api skill names writes " \
                        "it, such as /Shop/_apis/policy/configurations, or /_apis/projects for one outside a project. Classic release " \
                        "paths (/<project>/_apis/release/...) are read on their own host. api-version is 7.1 unless query gives it, " \
                        "such as 7.1-preview.1 for a preview read. A list answers one page: pass $top and read on with the " \
                        "continuationToken or $skip the reference names. Only reads, so it never changes anything. Variables, " \
                        "service connections and service hooks come back as their names",
           params_schema: ApiReads.path_schema("/Shop/_apis/policy/configurations"),
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN, label: "Personal access token", secret: true, placeholder: "Paste a token",
                              hint: "Create one in Azure DevOps under User settings, Personal access tokens, for this organization. " \
                                    "Reading needs Code, Build, Release and Project and Team (Read), and Environment (Read & manage). " \
                                    "Running or canceling pipelines needs Build (Read & execute), approvals Pipeline Resources (Use), " \
                                    "pull request comments Code (Read & write), and live updates Service Hooks (Read, query, & manage) from a project administrator.")
        ]
      end

      # Lists each project chosen (the project connect field) with the token, or lists the projects for every one it can
      # read, so a wrong organization, project or token is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[TOKEN].to_s.strip
        fields = fields.to_h
        projects = Array(fields[PROJECT]).map { |each| each.to_s.strip }.compact_blank
        return "Paste a personal access token." if token.empty?
        return "Choose at least one project, or all the token can read." if projects.empty?

        api = AzureDevopsApi.new(fields[ORGANIZATION], token)
        if projects == [ IntegrationProvider::ConnectField::ALL ]
          return listed_projects(api).empty? ? "This token can read no projects in #{api.organization}." : nil
        end

        project = nil
        projects.each do |each|
          project = each
          api.get("/_apis/projects/#{Http.segment(each)}")
        end
        nil
      rescue AzureDevopsApi::NotFound
        "Azure DevOps has no project #{project} in this organization that this token can see."
      rescue AzureDevopsApi::Refused => error
        Sentence.join("Azure DevOps refused this token", error, after: "Check it is active, made for this organization, and has #{SCOPES_WORDS}")
      rescue AzureDevopsApi::Error => error
        Sentence.join("Azure DevOps could not be reached with this organization and token", error)
      end

      # The projects the token can read in the organization (Projects - List, which needs Project and Team (Read)).
      def self.scope_options(values, region: nil, fields: {})
        token = values.to_h.stringify_keys[TOKEN].to_s.strip
        raise NativePack::Error, "Paste a personal access token first." if token.empty?

        listed_projects(AzureDevopsApi.new(fields.to_h[ORGANIZATION], token)).map { |project| IntegrationProvider::ConnectOption.new(value: project["name"], label: project["name"]) }
      rescue AzureDevopsApi::Error => error
        raise NativePack::Error, Sentence.join("Azure DevOps did not list this token's projects", error, after: "Listing them needs Project and Team (Read)")
      end

      def self.listed_projects(api) = api.list("/_apis/projects", { "$top" => AzureDevopsApi::PAGE_SIZE }, pages: MAX_PROJECT_PAGES).first
      private_class_method :listed_projects

      # A tool names the repository it acts on, or the pipeline or project, each starting with its project.
      def self.scope_references(arguments) = [ arguments["repo"], arguments["pipeline"], *Array(arguments["repos"]) ]

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(TOKEN, values[TOKEN].to_s.strip)
      end

      def list_repositories(environment_row:, arguments:)
        if every_scope?(environment_row)
          return ConnectionSettings.of(environment_row).scopes.map { |each| "Project #{each}:\n#{scoped(each).list_repositories(environment_row: environment_row, arguments: arguments)}" }.join("\n\n")
        end

        project = scope!(environment_row)
        repositories = repositories_of(api(environment_row), project)
        return "Project #{project} has no Git repositories this token can see." if repositories.empty?

        repositories.map do |repository|
          disabled = repository["isDisabled"] ? "  disabled" : ""
          "#{project}/#{repository['name']}  default branch #{branch_name(repository['defaultBranch']) || 'none'}#{disabled}  #{repository['webUrl']}"
        end.join("\n")
      end

      def pr_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        id = Integer(arguments["id"].to_s, exception: false)
        fail! "id must be the pull request's number" unless id&.positive?

        azure = api(environment_row)
        request = azure.get("#{path_of(repo)}/pullrequests/#{id}")
        files, more = pull_request_changes(azure, repo, id, pages: 1)
        Telemetry.result(<<~TEXT, link: link(pull_request_page(azure, repo, id)))
          PR !#{id}: #{request['title']}
          Status: #{pull_state(request)}
          Author: #{request.dig('createdBy', 'displayName')}
          Branch: #{branch_name(request['sourceRefName'])} -> #{branch_name(request['targetRefName'])}
          Merge commit: #{request.dig('lastMergeCommit', 'commitId') || 'none yet'}
          Reviewers: #{reviewer_votes(request).presence || 'none'}
          Changes: #{files.size}#{'+' if more} files

          #{file_lines(files, more)}
          #{request['description'].presence || '(no description)'}
        TEXT
      end

      def commit_lookup(environment_row:, arguments:)
        repo = repo_argument(arguments)
        azure = api(environment_row)
        sha = resolve_commit(azure, repo, commit_reference(arguments))
        commit = azure.get("#{path_of(repo)}/commits/#{sha}", "changeCount" => COMPARE_CHANGES)
        files = Array(commit["changes"]).filter_map { |change| changed_file(change) }
        Telemetry.result(<<~TEXT, link: link(commit["remoteUrl"]))
          Commit #{commit['commitId']}
          Author: #{commit.dig('author', 'name')} at #{commit.dig('author', 'date')}

          #{commit['comment']}

          #{file_lines(files, commit['commitTooManyChanges'] == true)}
        TEXT
      end

      def merged_pull_requests(environment_row:, arguments:)
        repo = repo_argument(arguments)
        since = since_argument(arguments)
        query = { "searchCriteria.status" => COMPLETED, "searchCriteria.queryTimeRangeType" => "closed", "searchCriteria.minTime" => since&.iso8601,
                  "$top" => MERGED_CANDIDATES }
        azure = api(environment_row)
        merged = azure.values(azure.get("#{path_of(repo)}/pullrequests", query)).select { |request| request["closedDate"].present? }
                      .sort_by { |request| request["closedDate"].to_s }.reverse.first(MERGED_LIMIT)
        return "No pull requests completed#{since ? " since #{since.iso8601}" : ''} in #{repo}." if merged.empty?

        merged.map do |request|
          "PR !#{request['pullRequestId']}  #{request['title']}  completed #{request['closedDate']} by #{request.dig('closedBy', 'displayName') || 'unknown'} " \
            "into #{branch_name(request['targetRefName'])}  #{pull_request_page(azure, repo, request['pullRequestId'])}"
        end.join("\n")
      end

      # The commits come from git in the sandbox, since the API names commits in a range only from where each is
      # reachable, and the diffs too, since the API's diff names the changed files without their lines.
      def compare_commits(environment_row:, arguments:)
        repo = repo_argument(arguments)
        base = ref_argument(arguments, "base", required: true)
        head = ref_argument(arguments, "head", required: true)
        azure = api(environment_row)
        diff = azure.get("#{path_of(repo)}/diffs/commits", "baseVersion" => base, "baseVersionType" => version_type(azure, repo, base),
                                                           "targetVersion" => head, "targetVersionType" => version_type(azure, repo, head),
                                                           "diffCommonCommit" => false, "$top" => COMPARE_CHANGES)
        changes = Array(diff["changes"]).filter_map { |change| changed_file(change) }
        commits, patches, unread = sandbox_range(environment_row, repo, base, head)
        files = changes.map { |file| file.merge(patch_counts(patches[file["filename"]])) }
        Capabilities::Comparison.with_comparison(
          comparison_text(azure, repo, base, head, diff, commits, files, unread),
          commits: commits ? commits.size : diff["aheadCount"].to_i, titles: Array(commits).map { |commit| "#{commit['id'][0, 12]} #{commit['title']}" },
          paths: files.map { |file| file["filename"] }, complete: diff["allChangesIncluded"] == true && commits.present?,
          link: commit_link(azure, repo, diff["targetCommit"])&.url
        )
      end

      def fetch_file(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        ref = ref_argument(arguments)
        azure = api(environment_row)
        commit = ref ? resolve_commit(azure, repo, ref) : nil
        item = read_item(azure, repo, path, commit)
        fail! "#{path} is a binary file, so it is not shown." if item.dig("contentMetadata", "isBinary")

        lines = item["content"].to_s.lines
        from, to = slice_range(arguments, lines.size)
        Telemetry.result("#{path}:#{from}-#{to} (of #{lines.size} lines) at #{ref || 'the default branch'}, commit #{item['commitId'].to_s[0, 12]}\n" \
                         "#{lines.empty? ? '(empty file)' : numbered(lines, from, to)}", link: commit_link(azure, repo, item["commitId"]))
      end

      def blame(environment_row:, arguments:)
        repo = repo_argument(arguments)
        path = path_argument(arguments)
        from, to = line_range!(arguments)
        ref = ref_argument(arguments)
        result = code(environment_row).exec(repo, ref: ref, where: Sandboxes::Client::IN_GIT,
                                                  argv: [ "blame", "--porcelain", "-L", "#{from},#{to}", Sandboxes::Client::COMMIT, "--", path ])
        fail! "No blame for '#{path}' at #{ref || 'the default branch'}: #{result['stderr'].to_s.strip.lines.last}" unless result["exit_code"].to_i.zero?

        ranges = blame_ranges(result["stdout"].to_s)
        fail! "No blame for '#{path}' at #{ref || 'the default branch'}." if ranges.empty?

        azure = api(environment_row)
        Telemetry.result(blame_text(azure, repo, path, ref, ranges, from, to), link: commit_link(azure, repo, result["commit"]))
      end

      # The projects' repositories and pipelines, and the infrastructure defined as code in the repositories, so the map
      # knows what each one manages and what builds it. Read once a day, and on Sync now.
      EVERY = 1.day

      def map_of(environment_row)
        map_of_scopes(environment_row, kinds: [ ResourceMap::KIND_REPOSITORY, ResourceMap::KIND_PIPELINE ]) { |pack| pack.map_of_project(environment_row) }
      end

      def map_of_project(environment_row)
        azure = api(environment_row)
        project = scope!(environment_row)
        repositories = repositories_of(azure, project).reject { |repository| repository["isDisabled"] }
        definitions, more = azure.list("#{AzureDevopsApi.project(project)}/_apis/build/definitions",
                                       { "includeAllProperties" => true, "includeLatestBuilds" => true, "$top" => AzureDevopsApi::PAGE_SIZE }, pages: MAX_DEFINITION_PAGES)
        gaps = more ? [ ResourceMap::Gap.new(text: "Only the first #{definitions.size} pipelines of #{project} were listed.", kinds: [ ResourceMap::KIND_PIPELINE ]) ] : []
        project_snapshot(azure, project, repositories, definitions, gaps: gaps)
      rescue AzureDevopsApi::Refused => error
        raise unless repositories

        gap = Sentence.join("The pipelines of #{project} could not be read", error, after: "Reading them needs Build (Read)")
        project_snapshot(azure, project, repositories, [], gaps: [ ResourceMap::Gap.new(text: gap, kinds: [ ResourceMap::KIND_PIPELINE ]) ])
      end

      # Only the repository or pipeline a change named, read again as the sweep reads it, the repository with its
      # infrastructure files. Gone only when Azure DevOps answers not found for it. nil for a scope it cannot narrow to,
      # which a sweep reads.
      def map_refresh(environment_row, scope)
        name = scope.external_id.to_s
        return unless name.match?(REPO_FORMAT)

        project = name.split("/", 2).first
        settings = ConnectionSettings.of(environment_row)
        return ResourceMap::Snapshot.new(resources: []) unless settings.scopes.include?(project)

        pack = settings.several_scopes? ? scoped(project) : self
        case scope.kind
        when nil, ResourceMap::KIND_REPOSITORY then pack.refreshed_repository(environment_row, name)
        when ResourceMap::KIND_PIPELINE then pack.refreshed_pipeline(environment_row, name)
        end
      end

      def refreshed_repository(environment_row, name)
        azure = api(environment_row)
        project, repository_name = project_and_name(name)
        repository = begin
          azure.get(AzureDevopsApi.repository(project, repository_name))
        rescue AzureDevopsApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, account_of(azure, project), ResourceMap::KIND_REPOSITORY, name ] ])
        end
        project_snapshot(azure, project, [ repository ], [], pipelines_read: false)
      end

      def refreshed_pipeline(environment_row, name)
        azure = api(environment_row)
        project, id = project_and_name(name)
        definition = begin
          azure.get("#{AzureDevopsApi.project(project)}/_apis/build/definitions/#{Integer(id, exception: false) || fail!("#{name} is not a pipeline's id.")}",
                    "includeLatestBuilds" => true)
        rescue AzureDevopsApi::NotFound
          return ResourceMap::Snapshot.new(resources: [], gone: [ [ PROVIDER_KEY, account_of(azure, project), ResourceMap::KIND_PIPELINE, name ] ])
        end
        project_snapshot(azure, project, [], [ definition ], repositories_read: false)
      end

      # Every repository in the project, the default branch with no refs/heads/ before it.
      def repositories_of(azure, project) = azure.values(azure.get("#{AzureDevopsApi.project(project)}/_apis/git/repositories"))

      # A GET the read guard let through (ReadGuards::AzureDevops). A path inside a project names it first, and that
      # project has to be one the connection reads, unless it reads every project its token can.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::AzureDevops.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        settings = ConnectionSettings.of(environment_row)
        first = URI.decode_www_form_component(path.delete_prefix("/").split("/").first.to_s)
        named = first unless first.start_with?("_")
        if named.nil? && !settings.all_scopes? && !ReadGuards::AzureDevops.organization_read?(path)
          fail_policy!("This connection reads the projects #{settings.chosen_scopes.to_sentence} only, so a read names one first, such as " \
                       "/#{settings.chosen_scopes.first}/_apis/git/repositories.")
        end
        outside = ApiReads.outside_scopes(settings, [ named ], "projects")
        fail_policy!(outside) if outside

        azure = api(environment_row)
        answer, continuation = azure.read(path, query)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::AzureDevops.secret?(path), webhooks: ReadGuards::AzureDevops.webhooks?(path))
        text += "\nMore follow. Read the next page with #{AzureDevopsApi::CONTINUATION_PARAM} #{continuation} in query." if continuation
        page = (answer.dig("_links", "web", "href") if answer.is_a?(Hash) && answer["_links"].is_a?(Hash) && answer.dig("_links", "web").is_a?(Hash))
        page ||= answer["webUrl"] if answer.is_a?(Hash) && answer["webUrl"].is_a?(String)
        page ||= project_page(azure, named) if named
        Telemetry.result(text, link: link(page))
      rescue AzureDevopsApi::Refused => error
        fail! Sentence.join("Azure DevOps refused this read", error, after: "The token's scopes do not reach it")
      end

      # The text files a handbook page is synced from, at path on the repository's default branch
      # (Integrations::RepositoryDocuments).
      def repository_documents(environment_row, repository:, path:)
        fail! "repository must be project/repository" unless repository.to_s.match?(REPO_FORMAT)

        azure = api(environment_row)
        CodeHost::Documents.new(Infrastructure.new(azure)).read(repository_of(azure.get(path_of(repository.to_s))), path)
      end

      # Reads each project the connection reaches, so one the token can no longer read is said on the connection.
      def check_health!(environment_row)
        azure = api(environment_row)
        ConnectionSettings.of(environment_row).scopes.each { |project| azure.get("/_apis/projects/#{Http.segment(project)}") }
      rescue AzureDevopsApi::Error => error
        fail! error.message
      end

      # An address of a pull request as Azure DevOps writes it, <organization>/<project>/_git/<repository>/pullrequest/<id>
      # (the pull request events' samples), with each part encoded.
      PULL_REQUEST_ADDRESS = %r{\Ahttps://dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/?#]+)/pullrequest/(\d+)(?:[/?#]|\z)}i

      # A pull request's repository and number, read from its address in this connection's organization, or nil for any
      # other address and for one outside the projects this connection reads (Integrations::PullRequests.addressed).
      def pull_request_at(environment_row, url)
        found = url.to_s.strip.match(PULL_REQUEST_ADDRESS)
        settings = ConnectionSettings.of(environment_row)
        return unless found && URI.decode_www_form_component(found[1]).casecmp?(settings.field(ORGANIZATION).to_s)

        project = URI.decode_www_form_component(found[2])
        return unless settings.scopes.any? { |each| each.to_s.casecmp?(project) }

        [ "#{project}/#{URI.decode_www_form_component(found[3])}", found[4].to_i ]
      end

      # Every path a pull request changes, a renamed file under both names (Integrations::PullRequests.paths). A list
      # Azure DevOps cuts short is refused rather than taken for the whole.
      def pull_request_paths(environment_row, repository:, number:)
        files, more = pull_request_changes(api(environment_row), repository, number, pages: FLAG_CHANGE_PAGES)
        fail! "PR !#{number} in #{repository} changes more files than Azure DevOps lists." if more

        files.flat_map { |file| [ file["filename"], file["previous"] ] }.compact.uniq
      rescue AzureDevopsApi::Error => error
        fail! error.message
      end

      # A comment thread on the pull request, written with the connection's token, which needs Code (Read & write)
      # (Pull Request Threads - Create, a thread with one text comment, commentType 1, active, status 1).
      def flag_pull_request(environment_row, repository:, number:, body:)
        api(environment_row).post("#{path_of(repository)}/pullRequests/#{number}/threads",
                                  { "comments" => [ { "parentCommentId" => 0, "content" => body, "commentType" => 1 } ], "status" => 1 })
        nil
      rescue AzureDevopsApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(TOKEN)
        fail! "This environment has no Azure DevOps token. Reconnect it on the Integrations page." if token.blank?

        AzureDevopsApi.new(settings.field(ORGANIZATION), token)
      rescue AzureDevopsApi::Error => error
        fail! error.message
      end

      def visible_repositories(environment_row)
        return ConnectionSettings.of(environment_row).scopes.flat_map { |each| scoped(each).send(:visible_repositories, environment_row) } if every_scope?(environment_row)

        project = scope!(environment_row)
        repositories_of(api(environment_row), project).reject { |repository| repository["isDisabled"] }.map { |repository| "#{project}/#{repository['name']}" }
      end

      # The sandbox fetches from the organization's Azure Repos address, <project>/_git/<repository>, with the token as
      # the password, and never follows a redirect.
      def code_remote(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(TOKEN)
        fail! "This environment has no Azure DevOps token. Reconnect it on the Integrations page." if token.blank?

        root = "https://#{AzureDevopsApi::HOST}/#{Http.segment(settings.field(ORGANIZATION))}"
        address = ->(repository) { project_and_name(repository).then { |project, name| "#{Http.segment(project)}/_git/#{Http.segment(name)}" } }
        CodeReading::Remote.new(host: AzureDevopsApi::HOST, root: root, user: GIT_USER, token: -> { token }, options: [ "http.followRedirects=false" ], address: address)
      end

      def repo_argument(arguments)
        repo = arguments["repo"].to_s.strip
        fail! "repo must be project/repository, such as Shop/checkout" unless repo.match?(REPO_FORMAT) && repo.split("/").none? { |part| part.strip.match?(/\A\.*\z/) }

        repo
      end

      def project_and_name(repo) = repo.to_s.split("/", 2)

      def path_of(repo) = AzureDevopsApi.repository(*project_and_name(repo))

      # The map's account for a project, which says the organization too, since two organizations can name a project alike.
      def account_of(azure, project) = "#{azure.organization}/#{project}"

      def branch_name(ref) = ref.to_s.delete_prefix(HEADS).presence

      def link(url) = url.present? ? Telemetry::Link.new(provider: PROVIDER, url: url) : nil

      # A repository in the shape the infrastructure reader and the sandbox take.
      def repository_of(repository)
        { "id" => repository["id"], "full_name" => "#{repository.dig('project', 'name')}/#{repository['name']}", "default_branch" => branch_name(repository["defaultBranch"]),
          "url" => repository["webUrl"], "size" => repository["size"].to_i, "archived" => repository["isDisabled"] == true, "fork" => repository["isFork"] == true }
      end

      # The repositories and pipelines as the map has them, each pipeline built from the repository its definition names.
      # A repository on another code host is put on the map as that host's reader puts it. A file left unread holds back
      # a suggestion, never a resource.
      def project_snapshot(azure, project, repositories, definitions, gaps: [], repositories_read: true, pipelines_read: true)
        account = account_of(azure, project)
        infrastructure = Infrastructure.new(azure)
        files = repositories_read ? infrastructure.files(repositories.map { |repository| repository_of(repository) }) : []
        found = repositories.map do |repository|
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_REPOSITORY, external_id: "#{project}/#{repository['name']}",
                                 name: "#{project}/#{repository['name']}", url: repository["webUrl"],
                                 details: { "branch" => branch_name(repository["defaultBranch"]) }.compact)
        end
        links = []
        pages = repositories.to_h { |repository| [ repository["id"], repository["webUrl"] ] }
        definitions.each do |definition|
          pipeline = pipeline_found(account, project, definition)
          found << pipeline
          source = built_from(azure, account, project, definition["repository"].to_h, pages)
          next unless source

          found << source unless found.any? { |each| each.key == source.key }
          links << ResourceMap::FoundLink.new(from: pipeline.key, to: source.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
        unread_files = infrastructure.gaps.map { |text| ResourceMap::Gap.new(text: text, kinds: []) }
        ResourceMap::Snapshot.new(resources: found, links: links, gaps: [ *gaps, *unread_files ], code_files: files, code_read: infrastructure.read_in_full)
      end

      # A pipeline reads as its newest finished run went, or as switched off when its queue is paused or disabled.
      def pipeline_found(account, project, definition)
        status = definition["queueStatus"].to_s == "enabled" || definition["queueStatus"].blank? ? definition.dig("latestCompletedBuild", "result") : definition["queueStatus"]
        name = [ definition["path"].to_s.delete_prefix("\\").tr("\\", "/").presence, definition["name"] ].compact.join("/")
        ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_PIPELINE, external_id: "#{project}/#{definition['id']}",
                               name: "#{project}/#{name}", status: status, url: definition.dig("_links", "web", "href"),
                               details: { "repository" => definition.dig("repository", "name"), "branch" => branch_name(definition.dig("repository", "defaultBranch")) }.compact)
      end

      # A pipeline building a repository read in the same sweep takes its page from there, and one read alone asks for it.
      def built_from(azure, account, project, repository, pages)
        return if repository["name"].blank?
        return ResourceMap.repository_of(repository["url"]) unless repository["type"] == AZURE_REPOS

        name = "#{project}/#{repository['name']}"
        page = pages.fetch(repository["id"]) { repository_page(azure, name) }
        ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: ResourceMap::KIND_REPOSITORY, external_id: name, name: name, url: page)
      end

      # A ref read as the commit it points at now: a SHA as it is, else a branch, else a tag (Refs - List, filter, and
      # peelTags for an annotated tag's commit).
      def resolve_commit(azure, repo, ref)
        return ref.downcase if ref.match?(SHA_FORMAT)

        [ "heads/#{ref}", "tags/#{ref}" ].each do |filter|
          found = azure.values(azure.get("#{path_of(repo)}/refs", "filter" => filter, "peelTags" => true)).find { |each| each["name"] == "refs/#{filter}" }
          return found["peeledObjectId"].presence || found["objectId"] if found
        end
        fail! "#{ref} is no commit, branch or tag in #{repo}."
      rescue AzureDevopsApi::NotFound
        fail! "#{repo} is no repository this token can see."
      end

      # What a diff's version names: a commit, a branch or a tag (GitVersionType).
      def version_type(azure, repo, ref)
        return "commit" if ref.match?(SHA_FORMAT)

        filter = "heads/#{ref}"
        azure.values(azure.get("#{path_of(repo)}/refs", "filter" => filter)).any? { |each| each["name"] == "refs/#{filter}" } ? "branch" : "tag"
      end

      def read_item(azure, repo, path, commit)
        version = commit ? { "versionDescriptor.version" => commit, "versionDescriptor.versionType" => "commit" } : {}
        azure.get("#{path_of(repo)}/items", { "path" => "/#{path}", "includeContent" => true, "includeContentMetadata" => true, "$format" => "json" }.merge(version))
      rescue AzureDevopsApi::NotFound
        fail! "No file at '#{path}' #{commit ? "at #{commit[0, 12]}" : 'on the default branch'}."
      end

      # A repository's page, the webUrl Azure DevOps gives for it, read once a call.
      def repository_page(azure, repo)
        @repository_pages ||= {}
        return @repository_pages[repo] if @repository_pages.key?(repo)

        @repository_pages[repo] = azure.get(path_of(repo))["webUrl"].presence
      rescue AzureDevopsApi::Error
        @repository_pages[repo] = nil
      end

      # A project's page, the _links.web Projects - Get answers for it, read once a call.
      def project_page(azure, project)
        @project_pages ||= {}
        return @project_pages[project] if @project_pages.key?(project)

        @project_pages[project] = azure.get("/_apis/projects/#{Http.segment(project)}").dig("_links", "web", "href").presence
      rescue AzureDevopsApi::Error
        @project_pages[project] = nil
      end

      # A commit's page under its repository's, as a commit's own remoteUrl writes it (Commits - Get).
      def commit_link(azure, repo, commit)
        page = repository_page(azure, repo)
        link("#{page}/commit/#{commit}") if page && commit.present?
      end

      # A pull request's page under its repository's, as the pull request events write it (Service hook events).
      def pull_request_page(azure, repo, id)
        page = repository_page(azure, repo)
        "#{page}/pullrequest/#{id}" if page
      end

      def pull_state(request)
        return "completed at #{request['closedDate']} by #{request.dig('closedBy', 'displayName') || 'unknown'}" if request["status"] == COMPLETED

        draft = request["isDraft"] ? ", draft" : ""
        "#{request['status']}#{draft}"
      end

      # Each reviewer with the vote Azure DevOps keeps for them, a team's vote rolled up from its members.
      def reviewer_votes(request)
        words = { 10 => "approved", 5 => "approved with suggestions", 0 => "no vote", -5 => "waiting for author", -10 => "rejected" }
        Array(request["reviewers"]).map { |reviewer| "#{reviewer['displayName']} #{words.fetch(reviewer['vote'].to_i, 'no vote')}#{' (required)' if reviewer['isRequired']}" }.join(", ")
      end

      def approvers(request) = Array(request["reviewers"]).select { |reviewer| APPROVED_VOTES.include?(reviewer["vote"].to_i) }.map { |reviewer| reviewer["displayName"] }

      # The files the newest iteration of a pull request changes against the target branch, a page of CHANGES_PAGE at a
      # time while nextSkip says more (Pull Request Iterations - List, Pull Request Iteration Changes - Get).
      def pull_request_changes(azure, repo, id, pages:)
        iterations = azure.values(azure.get("#{path_of(repo)}/pullRequests/#{id}/iterations"))
        last = iterations.map { |iteration| iteration["id"].to_i }.max
        return [ [], false ] unless last

        files = []
        skip = 0
        pages.times do
          answer = azure.get("#{path_of(repo)}/pullRequests/#{id}/iterations/#{last}/changes", "$top" => CHANGES_PAGE, "$skip" => skip)
          files.concat(Array(answer["changeEntries"]).filter_map { |change| changed_file(change) })
          skip = answer["nextSkip"].to_i
          return [ files, false ] if skip.zero?
        end
        [ files, true ]
      end

      # A change in the shape the change summaries read: filename, status, and the path it had before a rename. A folder
      # is not a file.
      def changed_file(change)
        item = change["item"].to_h
        return if item["isFolder"] || item["gitObjectType"] == "tree" || item["path"].blank?

        type = change["changeType"].to_s
        status = if type.include?("add") then "added"
        elsif type.include?("delete") then "removed"
        elsif type.include?("rename") then "renamed"
        else "modified"
        end
        { "filename" => item["path"].delete_prefix("/"), "status" => status, "previous" => change["originalPath"]&.delete_prefix("/"),
          "patch" => "", "additions" => nil, "deletions" => nil }
      end

      def file_lines(files, more)
        listed = files.first(FILE_LIMIT).map do |file|
          counts = file["additions"] ? ", +#{file['additions']} -#{file['deletions']}" : ""
          "  #{file['filename']} (#{file['status']}#{counts})"
        end
        listed << "  ... more files than these" if more || files.size > FILE_LIMIT
        listed.join("\n")
      end

      # The commits between base and head and each file's patch, read with git in the sandbox, or nil and why it could
      # not be read.
      def sandbox_range(environment_row, repo, base, head)
        box = code(environment_row)
        # The box fills in the commit only as a whole argument, so the range is the commit and not what base reaches.
        log = box.exec(repo, ref: head, where: Sandboxes::Client::IN_GIT, argv: [ "log", "--format=%H%x09%an%x09%aI%x09%s", Sandboxes::Client::COMMIT, "^#{base}" ])
        raise Integrations::Error, log["stderr"].to_s.strip.lines.last.to_s unless log["exit_code"].to_i.zero?

        diff = box.exec(repo, ref: head, where: Sandboxes::Client::IN_GIT, argv: [ "diff", "--patch", "--end-of-options", base, Sandboxes::Client::COMMIT ])
        commits = log["stdout"].to_s.lines.map do |line|
          id, author, at, title = line.chomp.split("\t", 4)
          { "id" => id, "author" => author, "at" => at, "title" => title }
        end
        [ commits, patches_by_file(diff["stdout"].to_s), nil ]
      rescue Integrations::Error => error
        [ nil, {}, error.message ]
      end

      def patches_by_file(diff)
        diff.split(/^(?=diff --git )/).each_with_object({}) do |section, patches|
          header = section.lines.first.to_s.chomp.match(GIT_FILE)
          patches[header[2]] = shown_patch(header[2], section) if header
        end
      end

      def patch_counts(patch)
        return { "patch" => "" } if patch.nil?

        { "patch" => patch,
          "additions" => patch.lines.count { |line| line.start_with?("+") && !line.start_with?("+++") },
          "deletions" => patch.lines.count { |line| line.start_with?("-") && !line.start_with?("---") } }
      end

      def comparison_text(azure, repo, base, head, diff, commits, files, unread)
        notes = []
        notes << "Azure DevOps listed only the first #{files.size} changed files." unless diff["allChangesIncluded"] == true
        notes << "git in the sandbox could not read the range, so the commits and diffs are not shown: #{unread}" if unread
        [
          "#{commits ? commits.size : diff['aheadCount'].to_i} commits, #{files.size} files changed. Base #{base} (#{diff['baseCommit'].to_s[0, 12]}), " \
          "head #{head} (#{diff['targetCommit'].to_s[0, 12]}).#{" #{notes.join(' ')}" if notes.any?}",
          grouped_files(files),
          dependency_text(files),
          (pull_requests_text(azure, repo, commits) if commits),
          "Azure Repos names who must review a change in its branch policies, not in a file, so no owners are named here. " \
          "api_read of /#{project_and_name(repo).first}/_apis/policy/configurations reads them.",
          (diffs_text(files) if commits)
        ].compact.join("\n\n")
      end

      # Newest commits first, the pull requests that merged them, so a long range still names who to ask.
      def pull_requests_text(azure, repo, commits)
        lines = commits.map { |commit| "  #{commit['id'][0, 12]}  #{commit['at']}  #{commit['author']}  #{commit['title']}" }
        requests = pull_requests_of(azure, repo, commits.first(PULL_LOOKUP_LIMIT).map { |commit| commit["id"] }).uniq { |request| request["pullRequestId"] }
        text = "Commits, newest first:\n#{lines.join("\n")}"
        if requests.any?
          listed = requests.map do |request|
            approved = approvers(request)
            "  PR !#{request['pullRequestId']} #{request['title']} by #{request.dig('createdBy', 'displayName')}" \
              "#{approved.any? ? ", approved by #{approved.join(', ')}" : ', no approvals'} #{pull_request_page(azure, repo, request['pullRequestId'])}"
          end
          text += "\n\nPull requests:\n#{listed.join("\n")}"
        end
        text += "\n(Pull requests looked up for the newest #{PULL_LOOKUP_LIMIT} commits of #{commits.size}.)" if commits.size > PULL_LOOKUP_LIMIT
        text
      end

      # The pull requests that merged the commits (Pull Request Query - Get, type commit), in the order the commits come.
      def pull_requests_of(azure, repo, shas)
        return [] if shas.empty?

        answer = azure.post("#{path_of(repo)}/pullrequestquery", { "queries" => [ { "type" => "commit", "items" => shas } ] })
        found = Array(answer["results"]).first.to_h
        shas.flat_map { |sha| Array(found[sha]) }
      rescue AzureDevopsApi::Error
        []
      end

      def diffs_text(files)
        ordered = files.sort_by { |file| CodeChange::KINDS.index(CodeChange.kind_for(file["filename"])) }
        diffs = ordered.map { |file| "#{file['filename']}\n#{file['patch'].presence || '(no text diff, binary or not changed in content)'}" }
        "Diffs:\n\n#{diffs.join("\n\n")}"
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

      def blame_text(azure, repo, path, ref, ranges, from, to)
        rendered = ranges.map do |range|
          commit = range[:commit]
          "#{"L#{range[:from]}-#{range[:to]}".ljust(12)} #{commit['id'][0, 12]} #{commit['time']} #{commit['summary']} (#{commit['author']})"
        end
        distinct = ranges.map { |range| range[:commit]["id"] }.uniq
        requests = pull_requests_of(azure, repo, distinct.first(BLAME_PULL_REQUESTS)).uniq { |request| request["pullRequestId"] }
        merged = requests.any? ? "\nPull requests: #{requests.map { |request| "!#{request['pullRequestId']} #{Sentence.clean(request['title'])} #{pull_request_page(azure, repo, request['pullRequestId'])}" }.join(', ')}." : ""
        "#{path}:#{from}-#{to} at #{ref || 'the default branch'}\n#{rendered.join("\n")}\n\n" \
          "Commits touching this range: #{distinct.map { |sha| sha[0, 12] }.join(', ')}.#{merged} Use commit_lookup or pr_lookup for the full change."
      end
    end
  end
end
