module Integrations
  module MapReaders
    # Puts Supabase on the resource map. Every project the connection reaches is a database, and each of its branches is
    # a project ref of its own. It reads through Supabase's own server, with only the tools an admin switched on. The
    # tools and their answers are the ones supabase-community/supabase-mcp publishes in packages/mcp-server-supabase/src/tools,
    # account-tools.ts and branching-tools.ts. Each page address is the dashboard's, dashboard/project/<ref>, as Supabase's
    # documentation links it.
    class Supabase < RemoteReader
      PROVIDER = "supabase".freeze
      NAME = "Supabase".freeze
      LIST_PROJECTS = "list_projects".freeze
      LIST_BRANCHES = "list_branches".freeze
      DOMAIN = "supabase.co".freeze
      POOLER_DOMAIN = "pooler.supabase.com".freeze
      DIRECT_PORTS = [ 5432, 6543 ].freeze
      POOLER_PORTS = [ 5432, 6543 ].freeze
      HTTPS_PORT = 443

      # A project's page under the dashboard, the registry's site for Supabase.
      def self.page(site, ref, path = nil) = [ "#{site}/project/#{ref}", path ].compact.join("/")

      def initialize(...)
        super
        @resources = []
        @links = []
        @endpoints = []
      end

      def map
        scoped = settings&.field(Capabilities::Supabase::SCOPED_TO)
        if scoped
          # A connection scoped to one project has no account tools, so the project is known only by its ref.
          project({ "ref" => scoped })
          gap("This connection is scoped to project #{scoped}, and Supabase gives such a connection no project details, so it is named by its ref.", kinds: [])
        else
          kinds = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ]
          Array(objects(listing(LIST_PROJECTS, "projects", {}, kinds: kinds), "projects", kinds: kinds, key: "projects")).each { |project| project(project) }
        end
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps, endpoints: @endpoints)
      end

      private

      def project(project)
        ref = project["ref"].presence || project["id"]
        account = project["organization_slug"].presence || project["organization_id"].presence || ref
        database = ResourceMap::Found.new(
          provider: PROVIDER, account: account, kind: ResourceMap::KIND_DATABASE, external_id: ref, name: project["name"].presence || ref,
          status: project["status"], url: self.class.page(settings&.site, ref),
          details: { "engine" => ("Postgres #{project.dig('database', 'version')}" if project.dig("database", "version")), "region" => project["region"] }.compact
        )
        @resources << database
        addresses(database, ref)

        # A scoped connection's tools take no project, as the server fills it in.
        arguments = parameters(LIST_BRANCHES).empty? || parameters(LIST_BRANCHES).key?("project_id") ? { "project_id" => ref } : {}
        what = "branches of #{database.name}"
        branches = listing(LIST_BRANCHES, what, arguments, kinds: [ ResourceMap::KIND_BRANCH ])
        Array(objects(branches, what, kinds: [ ResourceMap::KIND_BRANCH ], key: "branches")).each do |branch|
          branch_ref = branch["project_ref"].presence || ref
          found = ResourceMap::Found.new(
            provider: PROVIDER, account: account, kind: ResourceMap::KIND_BRANCH, external_id: branch_ref, name: "#{database.name}/#{branch['name']}",
            status: branch["status"], url: self.class.page(settings&.site, branch_ref),
            details: { ResourceMap::PRODUCTION => branch["is_default"], "branch" => branch["git_branch"], "persistent" => branch["persistent"] }.compact
          )
          @resources << found
          @links << ResourceMap::FoundLink.new(from: found.key, to: database.key, relation: ResourceMap::RELATION_BRANCH_OF)
          # The default branch is the project itself, whose addresses the project already holds.
          addresses(found, branch_ref) unless branch_ref == ref
        end
      end

      # Where a project is reached, built from its ref in memory and only ever kept as digests
      # (https://supabase.com/docs/guides/database/connecting-to-postgres). Its own host takes direct connections on
      # Postgres's port and its dedicated pooler's on 6543. The shared pooler's hosts are numbered per cluster and
      # region, so they are matched by their domain with the ref the user's name carries (postgres.<ref>), in session
      # and transaction mode. The project's API address is what SUPABASE_URL holds.
      def addresses(found, ref)
        return if ref.blank? || workspace.nil?

        DIRECT_PORTS.each { |port| @endpoints << ResourceMap::Endpoint.at(resource: found.key, host: "db.#{ref}.#{DOMAIN}", port: port, workspace: workspace) }
        POOLER_PORTS.each do |port|
          @endpoints << ResourceMap::Endpoint.within(resource: found.key, domain: POOLER_DOMAIN, port: port, workspace: workspace, tenant: ref)
        end
        @endpoints << ResourceMap::Endpoint.at(resource: found.key, host: "#{ref}.#{DOMAIN}", port: HTTPS_PORT, workspace: workspace)
      end
    end
  end
end
