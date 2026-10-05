module Integrations
  module MapReaders
    # PlanetScale on the resource map: every organization the connection reaches, its databases and their branches. It
    # reads through PlanetScale's own server, with only the tools an admin switched on, so the map never reaches past the
    # allowlist. A tool that is off, or a list PlanetScale refuses, is a gap rather than a failed sweep.
    class Planetscale < RemoteReader
      PROVIDER = "planetscale".freeze
      NAME = "PlanetScale".freeze
      LIST_ORGANIZATIONS = "planetscale_list_organizations".freeze
      LIST_DATABASES = "planetscale_list_databases".freeze
      LIST_BRANCHES = "planetscale_list_branches".freeze
      PER_PAGE = 100
      MAX_PAGES = 10

      def initialize(...)
        super
        @resources = []
        @links = []
        @gaps = []
      end

      def map
        list(LIST_ORGANIZATIONS, "organizations", {}, kinds: ResourceMap::KINDS).each do |organization|
          org = organization["name"]
          databases = list(LIST_DATABASES, "databases in #{org}", { "organization" => org }, kinds: [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ])
          databases.each { |database| database(org, database) }
        end
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps)
      end

      private

      def database(org, database)
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: org, kind: ResourceMap::KIND_DATABASE, external_id: database["name"], name: database["name"],
          status: database["state"], url: database["html_url"],
          details: { "engine" => database["kind"], "plan" => database["plan"], "region" => database.dig("region", "display_name") }.compact
        )
        @resources << found

        where = { "organization" => org, "database" => database["name"] }
        list(LIST_BRANCHES, "branches of #{database['name']}", where, kinds: [ ResourceMap::KIND_BRANCH ]).each do |branch|
          branch_found = ResourceMap::Found.new(
            provider: PROVIDER, account: org, kind: ResourceMap::KIND_BRANCH, external_id: "#{database['name']}/#{branch['name']}",
            name: "#{database['name']}/#{branch['name']}", status: branch["state"], url: branch["html_url"],
            details: { ResourceMap::PRODUCTION => branch["production"], "region" => branch.dig("region", "display_name") }.compact
          )
          @resources << branch_found
          @links << ResourceMap::FoundLink.new(from: branch_found.key, to: found.key, relation: ResourceMap::RELATION_BRANCH_OF)
        end
      end

      # Every page of a list, up to MAX_PAGES. What could not be read is said once, in words. A list cut short at the
      # bound leaves kinds unread, so the sweep takes nothing past it as gone.
      def list(tool, what, path, kinds:)
        read = Pages.read(max_pages: MAX_PAGES) do |page|
          arguments = { "queryParameters" => { "page" => page || 1, "per_page" => PER_PAGE } }
          arguments["pathParameters"] = path if path.any?
          body = listing(tool, what, arguments, kinds: kinds)
          body ? [ Array(body["data"]), (body["next_page"].presence && (page || 1) + 1) ] : [ [], nil ]
        end
        gap("Only the first #{MAX_PAGES * PER_PAGE} #{what} were read.", kinds: kinds) if read.incomplete?
        read.items
      end
    end
  end
end
