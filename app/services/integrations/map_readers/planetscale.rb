module Integrations
  module MapReaders
    # PlanetScale on the resource map: every organization the connection reaches, its databases and their branches. It
    # reads through PlanetScale's own server, with only the tools an admin switched on, so the map never reaches past the
    # allowlist. A tool that is off, or a list PlanetScale refuses, is a gap rather than a failed sweep.
    class Planetscale
      PROVIDER = "planetscale".freeze
      LIST_ORGANIZATIONS = "planetscale_list_organizations".freeze
      LIST_DATABASES = "planetscale_list_databases".freeze
      LIST_BRANCHES = "planetscale_list_branches".freeze
      PER_PAGE = 100
      MAX_PAGES = 10

      # call_tool runs one of the connection's tools by its name and answers what it returned, or nil when the admin has
      # it switched off.
      def initialize(&call_tool)
        @call_tool = call_tool
        @resources = []
        @links = []
        @gaps = []
      end

      def map
        list(LIST_ORGANIZATIONS, "organizations", {}).each do |organization|
          org = organization["name"]
          list(LIST_DATABASES, "databases in #{org}", { "organization" => org }).each { |database| database(org, database) }
        end
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: @gaps.uniq)
      end

      private

      def database(org, database)
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: org, kind: ResourceMap::KIND_DATABASE, external_id: database["name"], name: database["name"],
          status: database["state"], url: database["html_url"],
          details: { "engine" => database["kind"], "plan" => database["plan"], "region" => database.dig("region", "display_name") }.compact
        )
        @resources << found

        list(LIST_BRANCHES, "branches of #{database['name']}", { "organization" => org, "database" => database["name"] }).each do |branch|
          branch_found = ResourceMap::Found.new(
            provider: PROVIDER, account: org, kind: ResourceMap::KIND_BRANCH, external_id: "#{database['name']}/#{branch['name']}",
            name: "#{database['name']}/#{branch['name']}", status: branch["state"], url: branch["html_url"],
            details: { "production" => branch["production"], "region" => branch.dig("region", "display_name") }.compact
          )
          @resources << branch_found
          @links << ResourceMap::FoundLink.new(from: branch_found.key, to: found.key, relation: ResourceMap::RELATION_BRANCH_OF)
        end
      end

      # Every page of a list, up to MAX_PAGES. What could not be read is said once, in words.
      def list(tool, what, path)
        rows = []
        (1..MAX_PAGES).each do |page|
          arguments = { "queryParameters" => { "page" => page, "per_page" => PER_PAGE } }
          arguments["pathParameters"] = path if path.any?
          body = read(tool, what, arguments)
          return rows unless body

          rows.concat(Array(body["data"]))
          return rows if body["next_page"].blank?
        end
        @gaps << "Only the first #{MAX_PAGES * PER_PAGE} #{what} were read."
        rows
      end

      def read(tool, what, arguments)
        result = @call_tool.call(tool, arguments)
        if result.nil?
          @gaps << "#{tool} is switched off for PlanetScale, so the #{what} are not on the map."
          return
        end

        text = Array(result["content"]).filter_map { |part| part["text"] }.join
        return JSON.parse(text) unless result["isError"]

        @gaps << "PlanetScale refused to list the #{what}: #{text.truncate(200)}"
        nil
      rescue JSON::ParserError
        @gaps << "PlanetScale answered the #{what} with something that is not JSON."
        nil
      end
    end
  end
end
