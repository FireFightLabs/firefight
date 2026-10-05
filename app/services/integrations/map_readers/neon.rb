module Integrations
  module MapReaders
    # Puts Neon on the resource map: every project the connection reaches, its branches, the computes that serve each
    # branch and the Postgres databases on each branch. It reads through Neon's own server, with only the tools an admin
    # switched on. The tools and their answers are the ones neondatabase/mcp-server-neon publishes in mcp/tools/generated,
    # which answers the Neon API's own objects through @neon/tools. Each page address is the console's, as that server
    # writes it in mcp/tools/handlers/urls.ts.
    class Neon < RemoteReader
      PROVIDER = "neon".freeze
      NAME = "Neon".freeze
      LIST_ORGANIZATIONS = "list_organizations".freeze
      LIST_PROJECTS = "list_projects".freeze
      LIST_BRANCHES = "list_branches".freeze
      LIST_COMPUTES = "list_postgres_endpoints".freeze
      LIST_DATABASES = "list_postgres_databases".freeze
      # list_projects answers every page unless given a limit, and takes at most this many.
      PROJECT_LIMIT = 400
      BRANCH_LIMIT = 500
      # Each branch's databases are one call, so a project with many preview branches is read for its busiest first.
      DATABASE_READS = 25

      # A page under the console, the registry's site for Neon.
      def self.project_page(site, project_id) = "#{site}/app/projects/#{project_id}"

      def self.branch_page(site, project_id, branch_id) = "#{project_page(site, project_id)}/branches/#{branch_id}"

      ALL_KINDS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH, ResourceMap::KIND_COMPUTE ].freeze
      BRANCH_KINDS = [ ResourceMap::KIND_BRANCH, ResourceMap::KIND_COMPUTE ].freeze
      # Neon gives a project no state of its own, and one it lists is one it serves.
      LISTED = "ready".freeze

      def initialize(...)
        super
        @resources = []
        @links = []
      end

      def map
        organizations.each do |organization|
          arguments = { "limit" => PROJECT_LIMIT }
          arguments["org_id"] = organization["id"] if organization
          where = organization ? " in #{organization['name'] || organization['id']}" : ""
          projects = objects(listing(LIST_PROJECTS, "projects#{where}", arguments, kinds: ALL_KINDS), "projects#{where}", kinds: ALL_KINDS, key: "projects")
          next unless projects

          gap("Only the first #{PROJECT_LIMIT} projects#{where} were read.", kinds: ALL_KINDS) if projects.size >= PROJECT_LIMIT
          projects.each { |project| project(project, organization) }
        end
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps)
      end

      private

      # Without the organization list, list_projects picks the organization itself when the account has one, so projects
      # in any other may be missed.
      def organizations
        listed = objects(listing(LIST_ORGANIZATIONS, "organizations", {}, kinds: ALL_KINDS), "organizations", kinds: ALL_KINDS, key: "organizations")
        listed.present? ? listed : [ nil ]
      end

      def project(project, organization)
        id = project["id"]
        account = project["org_name"].presence || organization&.dig("name").presence || project["org_id"].presence || project["owner_id"].to_s
        database = ResourceMap::Found.new(
          provider: PROVIDER, account: account, kind: ResourceMap::KIND_DATABASE, external_id: id, name: project["name"].presence || id,
          status: LISTED, url: self.class.project_page(settings&.site, id),
          details: { "engine" => ("Postgres #{project['pg_version']}" if project["pg_version"]), "region" => project["region_id"] }.compact
        )
        @resources << database

        what = "branches of #{database.name}"
        branches = objects(listing(LIST_BRANCHES, what, { "project_id" => id, "limit" => BRANCH_LIMIT }, kinds: BRANCH_KINDS), what, kinds: BRANCH_KINDS, key: "branches") || []
        gap("Only the first #{BRANCH_LIMIT} branches of #{database.name} were read.", kinds: BRANCH_KINDS) if branches.size >= BRANCH_LIMIT
        found = branches.to_h { |branch| [ branch["id"], branch(database, account, branch) ] }

        computes(database, account, found)
        databases(database, branches, found)
      end

      def branch(database, account, branch)
        branch_found = ResourceMap::Found.new(
          provider: PROVIDER, account: account, kind: ResourceMap::KIND_BRANCH, external_id: "#{database.external_id}/#{branch['id']}",
          name: "#{database.name}/#{branch['name']}", status: branch["current_state"], url: self.class.branch_page(settings&.site, database.external_id, branch["id"]),
          details: { ResourceMap::PRODUCTION => branch["default"], "protected" => branch["protected"], "logical_size" => branch["logical_size"] }.compact
        )
        @resources << branch_found
        @links << ResourceMap::FoundLink.new(from: branch_found.key, to: database.key, relation: ResourceMap::RELATION_BRANCH_OF)
        branch_found
      end

      # A branch is served by its computes, so it is unreachable when they are.
      def computes(database, account, branches)
        what = "computes of #{database.name}"
        endpoints = listing(LIST_COMPUTES, what, { "project_id" => database.external_id }, kinds: [ ResourceMap::KIND_COMPUTE ])
        Array(objects(endpoints, what, kinds: [ ResourceMap::KIND_COMPUTE ], key: "endpoints")).each do |endpoint|
          branch = branches[endpoint["branch_id"]]
          compute = ResourceMap::Found.new(
            provider: PROVIDER, account: account, kind: ResourceMap::KIND_COMPUTE, external_id: "#{database.external_id}/#{endpoint['id']}",
            name: endpoint["name"].presence || endpoint["id"], status: (endpoint["disabled"] ? "disabled" : endpoint["current_state"]),
            url: branch&.url || database.url,
            details: {
              "type" => endpoint["type"], "branch" => branch&.name&.delete_prefix("#{database.name}/"), "host" => endpoint["host"],
              "autoscaling" => ("#{endpoint['autoscaling_limit_min_cu']} to #{endpoint['autoscaling_limit_max_cu']} CU" if endpoint["autoscaling_limit_max_cu"])
            }.compact
          )
          @resources << compute
          @links << ResourceMap::FoundLink.new(from: branch.key, to: compute.key, relation: ResourceMap::RELATION_SERVED_BY) if branch
        end
      end

      # The Postgres databases on a branch go into its details, since a Neon project is the database a person names.
      def databases(database, branches, found)
        ordered = branches.sort_by { |branch| branch["updated_at"].to_s }.reverse.partition { |branch| branch["default"] }.flatten
        ordered.first(DATABASE_READS).each do |branch|
          what = "databases on #{database.name}/#{branch['name']}"
          listed = objects(listing(LIST_DATABASES, what, { "project_id" => database.external_id, "branch_id" => branch["id"] }, kinds: []), what, kinds: [], key: "databases")
          next unless listed

          index = @resources.index(found[branch["id"]])
          @resources[index] = @resources[index].with(details: @resources[index].details.merge("databases" => listed.filter_map { |each| each["name"] }.join(", ")))
        end
        return if branches.size <= DATABASE_READS

        gap("The databases on #{branches.size - DATABASE_READS} more branches of #{database.name} were not read, only on its default and latest #{DATABASE_READS}.",
            kinds: [])
      end
    end
  end
end
