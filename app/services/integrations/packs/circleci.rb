module Integrations
  module Packs
    # CircleCI for every project in every organization a personal API token's user belongs to, through CircleCI's own API
    # (Integrations::CircleciApi): each project's runs with their workflows and jobs, a job's steps and output, its tests
    # and artifacts, what each component deployed, and rerunning, cancelling, approving, running a pipeline and rolling
    # back when allowed. CircleCI's hosted MCP server has no way to run a pipeline, approve a held job, read deploys or
    # roll back (circleci-mcp-overview.adoc), which is why the pack reads the API itself. The tools that match the hosted
    # server's keep its names, so a skill reads either connection the same way. Each project is on the map as a pipeline,
    # built from its repository.
    class Circleci < NativePack
      include Packs::CodeHost

      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      PROVIDER = "CircleCI".freeze
      PROVIDER_KEY = Capabilities::Circleci::PROVIDER_KEY
      # The address segment the app writes for each kind of project slug (rename-organizations-and-repositories.adoc, and
      # the workflow address an outbound webhook carries, outbound-webhooks-reference.adoc).
      VCS_PAGE = { "gh" => "github", "github" => "github", "bb" => "bitbucket", "bitbucket" => "bitbucket", "circleci" => "circleci" }.freeze
      # The organizations whose project slugs are written with the organization's and project's names (gh/acme/web),
      # GitHub OAuth and Bitbucket Cloud ones. Any other is circleci/<organization id>/<project id>, read off a workflow.
      NAMED_SLUGS = %w[gh bb github bitbucket].freeze
      PIPELINES = "pipelines".freeze
      SLUG = "slug".freeze
      REPOSITORY = "repository".freeze
      BRANCH = "branch".freeze
      ORGANIZATION = "organization".freeze

      PROJECT_PARAM = { "type" => "string", "description" => "A project, by its slug such as gh/acme/web, its name, its id, or the address of the repository it builds, as list_projects shows it" }.freeze
      REPOSITORY_PARAM = { "type" => "string", "description" => "Instead of project, the address of the repository the project builds, such as https://github.com/acme/web (optional)" }.freeze

      # A project as the pack reads it: its id, name and organization, its slug when known, the repository it builds and
      # its default branch.
      Project = Data.define(:id, :name, :org_id, :org_name, :org_slug, :slug, :repository, :branch) do
        def initialize(slug: nil, repository: nil, branch: nil, **) = super

        def label = slug || "#{org_name}/#{name}"
      end

      include Runs
      include Changes
      include Deploys

      tool :list_projects,
           summary: "Lists the CircleCI projects with their organization and repository.",
           description: "Every CircleCI project in the organizations this token's user belongs to, with its slug, id, organization and " \
                        "the repository it builds when known. Use it first to find the project the other tools take",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :api_read,
           summary: "Reads other CircleCI data such as contexts, schedules and insights.",
           description: "Anything else CircleCI's API reads that the other tools do not cover, such as a project's schedules, contexts and " \
                        "their restrictions, insights and flaky tests, or an organization's settings. A GET to a path of CircleCI's " \
                        "API, starting with the version it reads, /v2 or /v3, as the API reference the circleci_api skill names writes " \
                        "it, such as /v2/insights/gh/acme/web/workflows. Only reads, so it never changes anything. Environment " \
                        "variables, checkout keys and webhooks come back as their names",
           params_schema: ApiReads.path_schema("/v2/insights/gh/acme/web/workflows"),
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "Personal API token", secret: true, placeholder: "CCIPAT_...",
                              hint: "A CircleCI personal API token, from User settings, Personal API Tokens. Make it as a dedicated user, such as Firefight, " \
                                    "so changes do not show as a teammate and the connection keeps working when someone leaves. It reaches every project in " \
                                    "the organizations its user belongs to. Rerunning, cancelling, approving, running a pipeline and rolling back need a grant " \
                                    "for a member, and live updates need the user to manage the projects' webhooks.")
        ]
      end

      # Reads the token's user, so a wrong token is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        return "Paste a personal API token." if token.empty?

        CircleciApi.new(token).me
        nil
      rescue CircleciApi::Error => error
        Sentence.join("CircleCI refused this token", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_projects(environment_row:, arguments:)
        read = projects_of(environment_row)
        return Telemetry.result("This token reaches no CircleCI projects.", link: nil) if read.items.empty?

        rows = read.items.map do |project|
          [ project.label, "id #{project.id}", "organization #{project.org_name}", ("builds #{project.repository}" if project.repository) ].compact.join(", ")
        end
        cut = read.incomplete? ? " Only the first #{rows.size} were read." : ""
        Telemetry.result("#{rows.size} CircleCI projects.#{cut}\n#{rows.join("\n")}", link: nil)
      end

      # A GET the read guard let through (ReadGuards::Circleci). The token reaches every organization its user belongs to,
      # and nothing narrows a read further.
      def api_read(environment_row:, arguments:)
        call = begin
          ReadGuards::Circleci.reading(ApiReads::TOOL, arguments)
        rescue ReadGuards::Refused => error
          fail!(error.message)
        end
        path, query = call.values_at("path", "query")
        answer = api(environment_row).read(path, query)
        text = ApiReads.answer(PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::Circleci.secret?(path), webhooks: ReadGuards::Circleci.webhooks?(path))
        Telemetry.result(text, link: Telemetry::Link.new(provider: PROVIDER, url: ConnectionSettings.of(environment_row).site))
      end

      # Every project on the map as a pipeline, built from its repository when CircleCI says which. A list cut short, or a
      # project whose repository could not be read, is a gap rather than taken as gone.
      def map_of(environment_row)
        read = projects_of(environment_row, deep: true)
        resources = []
        links = []
        read.items.each do |project|
          pipeline = pipeline_resource(environment_row, project)
          resources << pipeline
          repository = ResourceMap.repository_of(project.repository)
          next unless repository

          resources << repository
          links << ResourceMap::FoundLink.new(from: pipeline.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
        gaps = []
        gaps << ResourceMap::Gap.new(text: "Only the first #{read.items.size} CircleCI projects were read.", kinds: [ ResourceMap::KIND_PIPELINE, ResourceMap::KIND_REPOSITORY ]) if read.incomplete?
        gaps << ResourceMap::Gap.new(text: "CircleCI asked Firefight to slow down, so some projects' repositories are read at the next sweep.", kinds: [ ResourceMap::KIND_REPOSITORY ]) if @slowed
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)
      end

      def check_health!(environment_row)
        api(environment_row).me
      rescue CircleciApi::Error => error
        fail! error.message
      end

      # The page of a project's pipelines, of one run's workflow, or nil when the slug is not known, as the app writes them
      # (app.circleci.com/pipelines/<vcs>/<org>/<project>, and .../<number>/workflows/<id> as a webhook's workflow url is).
      def self.page(site, slug, number: nil, workflow: nil)
        vcs, organization, name, *rest = slug.to_s.split("/")
        return unless VCS_PAGE.key?(vcs) && organization.present? && name.present? && rest.empty?

        parts = [ site, PIPELINES, VCS_PAGE.fetch(vcs), organization, name ]
        parts += [ number, "workflows", workflow ] if number && workflow
        parts.map(&:to_s).join("/")
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no CircleCI token. Reconnect it on the Integrations page." if token.blank?

        @api ||= CircleciApi.new(token)
      end

      def site(environment_row) = ConnectionSettings.of(environment_row).site

      def link_to(url) = url.present? ? Telemetry::Link.new(provider: PROVIDER, url: url) : nil

      def project_link(environment_row, project)
        link_to(self.class.page(site(environment_row), project.slug)) || link_to(site(environment_row))
      end

      # Every project of every organization the token's user belongs to. deep reads what a sweep keeps beside each one,
      # its slug and repository, which a tool call reads only for the project it names.
      def projects_of(environment_row, deep: false)
        @projects ||= begin
          known = known_details(environment_row)
          complete = true
          items = api(environment_row).collaborations.flat_map do |organization|
            read = api(environment_row).projects(organization["id"])
            complete &&= read.complete
            read.items.map { |project| project_of(organization, project, known[project["id"].to_s]) }
          end
          Pages::Read.new(items: items, complete: complete)
        end
        return @projects unless deep && !@deepened

        @deepened = true
        @projects = @projects.with(items: @projects.items.map { |project| deepened(environment_row, project) })
      end

      def project_of(organization, project, known)
        org_slug = organization["slug"].to_s
        vcs = org_slug.split("/").first
        name = project.dig("attributes", "name").to_s
        slug = NAMED_SLUGS.include?(vcs) ? "#{org_slug}/#{name}" : known.to_h[SLUG]
        Project.new(id: project["id"].to_s, name: name, org_id: organization["id"].to_s, org_name: organization["name"].to_s, org_slug: org_slug,
                    slug: slug, repository: known.to_h[REPOSITORY], branch: known.to_h[BRANCH])
      end

      # What the map already holds for each project of this connection, so a slug read once off a workflow is not read again.
      def known_details(environment_row)
        ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, provider: PROVIDER_KEY, kind: ResourceMap::KIND_PIPELINE)
                             .where("resource_map_resources.integration_environment_id = :row OR resource_map_resources.sightings ? :row", row: environment_row.id.to_s)
                             .pluck(:external_id, :details).to_h
      end

      # The slug, repository and default branch of a project, from what CircleCI says: its slug off its newest run's
      # workflow (v2 getWorkflowById) when it is not written with names, then the repository and default branch from v2
      # getProjectBySlug, or else the repository its newest run built (target_repository_url). Being asked to slow down
      # stops these reads for the rest of the sweep.
      def deepened(environment_row, project)
        return project if @slowed

        slug = project.slug || slug_from_runs(environment_row, project)
        found = slug ? api(environment_row).project_by_slug(slug) : {}
        repository = found.dig("vcs_info", "vcs_url").presence || newest_run_repository(environment_row, project)
        project.with(slug: slug, repository: repository.presence || project.repository, branch: found.dig("vcs_info", "default_branch").presence || project.branch)
      rescue Integrations::RateLimited
        @slowed = true
        project
      rescue CircleciApi::Error
        project
      end

      def slug_from_runs(environment_row, project)
        run = api(environment_row).runs(project.id, limit: 1).first
        workflow = run && api(environment_row).workflows(run["id"]).first
        workflow && api(environment_row).workflow_summary(workflow["id"])["project_slug"].presence
      end

      def newest_run_repository(environment_row, project)
        run = api(environment_row).runs(project.id, limit: 1).first
        run.to_h.dig("references", "event", "attributes", "vcs", "target_repository_url")
      end

      # The project a call names, by id, slug, name or the address of the repository it builds, with its slug and repository.
      def find_project(environment_row, arguments)
        asked = arguments["project"].to_s.strip.presence || arguments[Capabilities::Circleci::REPOSITORY].to_s.strip.presence
        fail! "Say which project, by its slug, name or id, or the address of its repository. list_projects shows them." unless asked

        projects = projects_of(environment_row).items
        found = projects.find { |project| project.slug.to_s.casecmp?(asked) } ||
                (repository_project(projects, asked) if asked.include?("://")) ||
                Named.find(projects, asked, id: :id, name: :name, provider: PROVIDER, connection: environment_row)
        found ||= slug_project(environment_row, projects, asked)
        found || fail!("No CircleCI project #{asked} is reached by this token. list_projects shows what there is.")
        found.slug && found.repository ? found : deepened(environment_row, found)
      end

      # A repository's address matched against what the map read each project builds, or against the slug CircleCI writes
      # for a GitHub or Bitbucket repository.
      def repository_project(projects, address)
        wanted = address.chomp("/").delete_suffix(".git").downcase
        by_repository = projects.find { |project| project.repository.to_s.chomp("/").delete_suffix(".git").downcase == wanted }
        return by_repository if by_repository

        page = URI.parse(address)
        vcs = Capabilities::Circleci::VCS[page.host.to_s.downcase]
        path = page.path.to_s[Capabilities::Circleci::OWNER_AND_NAME, 1]
        vcs && path && projects.find { |project| project.slug.to_s.casecmp?("#{vcs}/#{path}") }
      rescue URI::InvalidURIError
        nil
      end

      # A slug the projects were not read with, such as circleci/<org>/<project>, resolved by CircleCI (v2 getProjectBySlug).
      def slug_project(environment_row, projects, slug)
        return unless slug.count("/") == 2

        found = api(environment_row).project_by_slug(slug)
        project = projects.find { |each| each.id == found["id"].to_s }
        project&.with(slug: found["slug"].presence || slug, repository: found.dig("vcs_info", "vcs_url").presence || project.repository,
                      branch: found.dig("vcs_info", "default_branch").presence || project.branch)
      rescue CircleciApi::NotFound
        nil
      end

      def pipeline_resource(environment_row, project)
        details = { SLUG => project.slug, REPOSITORY => project.repository, BRANCH => project.branch, ORGANIZATION => project.org_name }.compact
        ResourceMap::Found.new(provider: PROVIDER_KEY, account: project.org_name.presence || project.org_id, kind: ResourceMap::KIND_PIPELINE,
                               external_id: project.id, name: project.label, url: self.class.page(site(environment_row), project.slug), details: details)
      end
    end
  end
end
