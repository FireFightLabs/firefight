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
      GET_DATABASE = "planetscale_get_database".freeze
      GET_BRANCH = "planetscale_get_branch".freeze
      # PlanetScale's answer for something that is not there (planetscale.com/docs/api/reference, errors), which its server
      # hands back as the tool's error.
      NOT_FOUND = "not_found".freeze
      PER_PAGE = 100
      MAX_PAGES = 10
      MYSQL_PORT = 3306
      # A Postgres branch's hosts are named for an id and region the API does not give, all under this domain, on the
      # direct and the PgBouncer port (https://planetscale.com/docs/postgres/connecting/quickstart).
      POSTGRES_DOMAIN = "horizon.psdb.cloud".freeze
      POSTGRES_PORTS = [ 5432, 6432 ].freeze
      POSTGRES = "postgresql".freeze

      def initialize(...)
        super
        @resources = []
        @links = []
        @gaps = []
        @endpoints = []
      end

      # Everything the connection reaches, or with scope only the database or the branch a change named
      # (Integrations::MapEventSources::Planetscale), read as the sweep reads it. nil for a scope it cannot narrow to, or
      # when a tool the narrow read needs is off, which a sweep reads.
      def map(scope: nil)
        return refreshed(scope) if scope

        list(LIST_ORGANIZATIONS, "organizations", {}, kinds: ResourceMap::KINDS).each do |organization|
          org = organization["name"]
          databases = list(LIST_DATABASES, "databases in #{org}", { "organization" => org }, kinds: [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ])
          databases.each { |database| database(org, database) }
        end
        snapshot
      end

      private

      def refreshed(scope)
        return unless scope.account && scope.external_id && [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].include?(scope.kind)

        org = scope.account
        name, branch_name = scope.external_id.split("/", 2)
        one_branch = scope.kind == ResourceMap::KIND_BRANCH
        return if one_branch && branch_name.blank?
        return unless on?(GET_DATABASE) && on?(one_branch ? GET_BRANCH : LIST_BRANCHES)

        path = { "organization" => org, "database" => name }
        read_database = fetched(GET_DATABASE, path, "database #{name}")
        if read_database == NOT_FOUND
          return gone(org, [ ResourceMap::KIND_DATABASE, name ], *([ [ ResourceMap::KIND_BRANCH, scope.external_id ] ] if one_branch))
        end

        if one_branch
          read = fetched(GET_BRANCH, path.merge("branch" => branch_name), "branch #{scope.external_id}")
          return gone(org, [ ResourceMap::KIND_BRANCH, scope.external_id ]) if read == NOT_FOUND

          branch(org, read_database, database_found(org, read_database), read)
        else
          database(org, read_database)
        end
        snapshot
      end

      def snapshot = ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps, endpoints: @endpoints)

      # What PlanetScale answered not found for, by kind and name, and nothing else.
      def gone(org, *kinds_and_ids)
        ResourceMap::Snapshot.new(resources: [], gone: kinds_and_ids.map { |kind, id| [ PROVIDER, org, kind, id ] })
      end

      # One object a tool answers, NOT_FOUND when PlanetScale says it is not there, or raises with its words.
      def fetched(tool, path, what)
        result = call(tool, { "pathParameters" => path })
        raise Integrations::Error, "#{tool} is switched off for #{NAME}, so the #{what} could not be read again." if result.nil?

        answered = Capabilities::Answers.data(result)
        if result["isError"]
          return NOT_FOUND if answered.is_a?(Hash) && answered["code"] == NOT_FOUND

          raise Integrations::Error, Sentence.join("#{NAME} refused to read the #{what}", Capabilities::Answers.text(result).truncate(200))
        end
        return answered if answered.is_a?(Hash)

        raise Integrations::Error, "#{NAME} answered the #{what} with something that is not JSON."
      end

      def database_found(org, database)
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: org, kind: ResourceMap::KIND_DATABASE, external_id: database["name"], name: database["name"],
          status: database["state"], url: database["html_url"],
          details: { "engine" => database["kind"], "plan" => database["plan"], "region" => database.dig("region", "display_name") }.compact
        )
        @resources << found
        found
      end

      def database(org, database)
        found = database_found(org, database)
        where = { "organization" => org, "database" => database["name"] }
        list(LIST_BRANCHES, "branches of #{database['name']}", where, kinds: [ ResourceMap::KIND_BRANCH ]).each { |branch| branch(org, database, found, branch) }
      end

      # One branch of a database, linked to it, with where it is reached.
      def branch(org, database, found, branch)
        branch_found = ResourceMap::Found.new(
          provider: PROVIDER, account: org, kind: ResourceMap::KIND_BRANCH, external_id: "#{database['name']}/#{branch['name']}",
          name: "#{database['name']}/#{branch['name']}", status: branch["state"], url: branch["html_url"],
          details: { ResourceMap::PRODUCTION => branch["production"], "region" => branch.dig("region", "display_name") }.compact
        )
        @resources << branch_found
        @links << ResourceMap::FoundLink.new(from: branch_found.key, to: found.key, relation: ResourceMap::RELATION_BRANCH_OF)
        addresses(branch_found, database, branch)
      end

      # Where a branch is reached, from the branch object (https://planetscale.com/docs/api/reference/list_branches). A
      # Postgres branch's user is role.<branch id>, so the branch is matched exactly by its domain and its id. A MySQL
      # branch's mysql_address and mysql_edge_address are hosts many accounts share, told apart only by the database's
      # name, which every branch of a database also shares, so only the production branch is offered there, and only
      # as a likely match.
      def addresses(branch_found, database, branch)
        return if workspace.nil?

        if (branch["kind"].presence || database["kind"]) == POSTGRES
          POSTGRES_PORTS.each do |port|
            @endpoints << ResourceMap::Endpoint.within(resource: branch_found.key, domain: POSTGRES_DOMAIN, port: port, workspace: workspace, tenant: branch["id"])
          end
        elsif branch["production"]
          branch.values_at("mysql_address", "mysql_edge_address").compact_blank.uniq.each do |address|
            host, port = address.to_s.split(":", 2)
            @endpoints << ResourceMap::Endpoint.at(resource: branch_found.key, host: host, port: port.presence || MYSQL_PORT, workspace: workspace,
                                                   database: database["name"], shared: true)
          end
        end
      end

      # Every page of a list, up to MAX_PAGES. What could not be read is said once, in words. A list cut short at the
      # bound leaves kinds unread, so the sweep takes nothing past it as gone.
      def list(tool, what, path, kinds:)
        read = Pages.read(max_pages: MAX_PAGES) do |page|
          arguments = { "queryParameters" => { "page" => page || 1, "per_page" => PER_PAGE } }
          arguments["pathParameters"] = path if path.any?
          body = listing(tool, what, arguments, kinds: kinds)
          rows = objects(body, what, kinds: kinds, key: "data")
          rows ? [ rows, (body["next_page"].presence && (page || 1) + 1 if body.is_a?(Hash)) ] : [ [], nil ]
        end
        gap("Only the first #{MAX_PAGES * PER_PAGE} #{what} were read.", kinds: kinds) if read.incomplete?
        read.items
      end
    end
  end
end
