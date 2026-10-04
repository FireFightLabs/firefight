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
        @gaps = []
      end

      def map
        projects = read(LIST_PROJECTS, "projects", {})
        Array(projects&.dig("projects")).each { |project| project(project) }
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: @gaps.uniq)
      end

      private

      def project(project)
        ref = project["ref"].presence || project["id"]
        account = project["organization_slug"].presence || project["organization_id"].to_s
        database = ResourceMap::Found.new(
          provider: PROVIDER, account: account, kind: ResourceMap::KIND_DATABASE, external_id: ref, name: project["name"].presence || ref,
          status: project["status"], url: self.class.page(settings&.site, ref),
          details: { "engine" => ("Postgres #{project.dig('database', 'version')}" if project.dig("database", "version")), "region" => project["region"] }.compact
        )
        @resources << database

        branches = read(LIST_BRANCHES, "branches of #{database.name}", { "project_id" => ref })
        Array(branches&.dig("branches")).each do |branch|
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

      # A connection scoped to one project offers no list_projects, so it is said rather than taken as an empty account.
      def read(tool, what, arguments)
        result = call(tool, arguments)
        if result.nil?
          @gaps << "#{tool} is switched off for #{NAME}, or the connection is scoped to one project, so the #{what} are not on the map."
          return
        end

        text = Array(result["content"]).filter_map { |part| part["text"] }.join
        return JSON.parse(text) unless result["isError"]

        @gaps << "#{NAME} refused to list the #{what}: #{text.truncate(200)}"
        nil
      rescue JSON::ParserError
        @gaps << "#{NAME} answered the #{what} with something that is not JSON."
        nil
      end
    end
  end
end
