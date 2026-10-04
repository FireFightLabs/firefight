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

      # A project's page under the dashboard, the registry's site for Supabase.
      def self.page(site, ref, path = nil) = [ "#{site}/project/#{ref}", path ].compact.join("/")

      def initialize(...)
        super
        @resources = []
        @links = []
      end

      def map
        scoped = settings&.field(Capabilities::Supabase::SCOPED_TO)
        if scoped
          # A connection scoped to one project has no account tools, so the project is known only by its ref.
          project({ "ref" => scoped })
          gap("This connection is scoped to project #{scoped}, and Supabase gives such a connection no project details, so it is named by its ref.", kinds: [])
        else
          Array(listing(LIST_PROJECTS, "projects", {}, kinds: [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ])&.dig("projects")).each { |project| project(project) }
        end
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps)
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

        # A scoped connection's tools take no project, as the server fills it in.
        arguments = parameters(LIST_BRANCHES).empty? || parameters(LIST_BRANCHES).key?("project_id") ? { "project_id" => ref } : {}
        branches = listing(LIST_BRANCHES, "branches of #{database.name}", arguments, kinds: [ ResourceMap::KIND_BRANCH ])
        Array(branches.is_a?(Hash) ? branches["branches"] : nil).each do |branch|
          branch_ref = branch["project_ref"].presence || ref
          found = ResourceMap::Found.new(
            provider: PROVIDER, account: account, kind: ResourceMap::KIND_BRANCH, external_id: branch_ref, name: "#{database.name}/#{branch['name']}",
            status: branch["status"], url: self.class.page(settings&.site, branch_ref),
            details: { ResourceMap::PRODUCTION => branch["is_default"], "branch" => branch["git_branch"], "persistent" => branch["persistent"] }.compact
          )
          @resources << found
          @links << ResourceMap::FoundLink.new(from: found.key, to: database.key, relation: ResourceMap::RELATION_BRANCH_OF)
        end
      end
    end
  end
end
