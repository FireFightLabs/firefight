module Integrations
  module Packs
    class Northflank < NativePack
      # The templates of the team the connection's token belongs to. Northflank runs a template from the team rather than
      # a project, through /v1/templates, which answers for the token's own team (List templates, List template runs, Get
      # template run, Run template, Abort template run). A template defines infrastructure as one unit, so it is a stack on
      # the map, and its runs are its run history. A run is the same tree of nodes a workflow run is, and a node acts in
      # the project its own projectId or the context of the workflow holding it names (Write a template), so a node's log
      # is read only in a project this connection reaches. Starting or aborting a run is a change of its own, granted apart
      # from api_request, which never leaves a project.
      module Templates
        TEMPLATE_RUNS = "template_runs".freeze
        RUN_TEMPLATE = "run_template".freeze
        ABORT_TEMPLATE_RUN = "abort_template_run".freeze
        # The Templates page in Northflank's app, the one address its documentation gives for templates. It names no
        # template or run of its own.
        TEMPLATES_PAGE = "s/account/templates".freeze
        # A template's runs and one run in Northflank's app, under the team: templates/<template>/runs/<run>, as its app
        # builds them.
        TEMPLATES = "templates".freeze
        TEMPLATE_KIND = "template".freeze
        # How a node names a project made earlier in the same run, read from the run's refs.
        PROJECT_REFERENCE = /\A\$\{refs\.([A-Za-z0-9_-]+)\.id\}\z/
        NAMES_LISTED = 20
        NO_TEAM = "The team's templates go on the map once a project holds a service, whose address names the team.".freeze
        READ_PERMISSION ="Its role needs to read templates (Account, Templates, General, Read).".freeze
        RUN_PERMISSION = "The API token's role cannot run templates. In Northflank, give the role Account, Templates, General, Run, then run it again.".freeze
        ABORT_PERMISSION = "The API token's role cannot abort template runs. In Northflank, give the role Account, Templates, Runs, Abort, then run it again.".freeze
        History = Capabilities::History
        TEMPLATE = { "type" => "string", "description" => "The template, by name or id" }.freeze

        def self.included(pack)
          pack.tool TEMPLATE_RUNS,
                    summary: "Lists a template's recent runs and how each step went.",
                    description: "A Northflank template's recent runs, newest first, each with its status, when it started and finished and how " \
                                 "long it took, and how long finished runs usually take. Templates belong to the team rather than a project. " \
                                 "Name a run to read it with each node, such as a project, a service, a build or a release, how each went, " \
                                 "the error a failed one gave and its retries",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "template" => TEMPLATE,
                        "name" => { "type" => "string", "description" => "Only runs whose template's name contains this (optional)" },
                        "run" => { "type" => "string", "description" => "Only this run, by its id, with each of its nodes (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{Releases::RUN_LIMIT})" }
                      },
                      "required" => [ "template" ]
                    },
                    read_only: true

          pack.tool RUN_TEMPLATE,
                    summary: "Starts a run of a template, creating or changing what it defines.",
                    description: "Start a run of a Northflank template, which creates or changes everything it defines across the team's " \
                                 "projects. Pass the values its ${args.<name>} read as arguments. Follow the run with run_history on the template",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "template" => TEMPLATE,
                        "arguments" => { "type" => "object", "description" => "Values the template reads as ${args.<name>}, by name, such as {\"version\": \"v1.4\"}. Never a secret (optional)" }
                      },
                      "required" => [ "template" ]
                    },
                    read_only: false

          pack.tool ABORT_TEMPLATE_RUN,
                    summary: "Aborts a running template run.",
                    description: "Abort a running Northflank template run. What its finished nodes already did stays in place",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "template" => TEMPLATE,
                        "run" => { "type" => "string", "description" => "The run, by its id, as run_history on the template shows it" }
                      },
                      "required" => %w[template run]
                    },
                    read_only: false
        end

        def template_runs(environment_row:, arguments:)
          template = template_named(environment_row, arguments["template"])
          name = template["name"].presence || template["id"]
          what = "template #{name}"
          link = template_runs_link(environment_row, template["id"]) || templates_link(environment_row)
          page_of = ->(run) { template_runs_link(environment_row, template["id"], run["id"])&.url }
          if arguments["run"].present?
            run = reading_templates { api(environment_row).template_run(template["id"], run_id(arguments)) }
            return History.result([ template_run(run, name, page_of.call(run)).with(parts: template_parts(run, environment_row)) ], what: what, link: link)
          end

          runs = reading_templates { api(environment_row).template_runs(template["id"], limit: limit(arguments, Releases::RUN_LIMIT)) }
          History.result(runs.map { |run| template_run(run, name, page_of.call(run)) }, what: what, link: link, name: arguments["name"],
                                                                                         limit: limit(arguments, Releases::RUN_LIMIT))
        end

        def run_template(environment_row:, arguments:)
          given = arguments["arguments"]
          fail!("arguments must be an object of names to values, such as {\"version\": \"v1.4\"}.") unless given.nil? || given.is_a?(Hash)
          fail_policy!("arguments hold what looks like a secret, and Firefight never sends a credential through Northflank's API.") if secret?(given)

          template = template_named(environment_row, arguments["template"])
          name = template["name"].presence || template["id"]
          run = changing_templates(RUN_PERMISSION) { api(environment_row).run_template(template["id"], given.presence) }
          Telemetry.result("Started run #{run['id']} of template #{name}, now #{run['status'] || 'pending'}. Follow it with run_history on the template.",
                           link: template_runs_link(environment_row, template["id"], run["id"]) || templates_link(environment_row))
        end

        def abort_template_run(environment_row:, arguments:)
          template = template_named(environment_row, arguments["template"])
          name = template["name"].presence || template["id"]
          id = run_id(arguments)
          run = changing_templates(ABORT_PERMISSION) { api(environment_row).abort_template_run(template["id"], id) }
          Telemetry.result("Asked Northflank to abort run #{id} of template #{name}, now #{run['status'] || 'aborting'}. What its finished nodes did stays in place.",
                           link: template_runs_link(environment_row, template["id"], id) || templates_link(environment_row))
        end

        # The team's templates on the map, once for the connection whichever projects it reaches, under the team its
        # projects' services named, so a connection with no service yet says so in the gaps. A token that may not read templates leaves words in the gaps and takes nothing else
        # off the map, and one that could not be read for another reason keeps the templates the map had.
        def with_templates(environment_row, snapshot)
          team = snapshot.resources.find { |found| found.provider == PROVIDER_KEY && found.account.to_s.include?("/") }&.account.to_s.split("/").first
          return snapshot.with(gaps: snapshot.gaps + [ ResourceMap::Gap.new(text: NO_TEAM, kinds: []) ]) if team.blank?

          listed = api(environment_row).templates
          mapping = MapReading.new(team) { |_kind, _id| nil }
          listed.items.each { |template| mapping.template(template) }
          gaps = listed.incomplete? ? [ ResourceMap::Gap.new(text: "Only the first #{listed.items.size} templates are on the map.", kinds: [ ResourceMap::KIND_STACK ]) ] : []
          snapshot.with(resources: snapshot.resources + mapping.resources, gaps: snapshot.gaps + gaps)
        rescue NorthflankApi::RateLimited
          raise
        rescue NorthflankApi::Forbidden => error
          snapshot.with(gaps: snapshot.gaps + [ ResourceMap::Gap.new(text: Sentence.all(Sentence.join("Templates could not be read", error), READ_PERMISSION), kinds: []) ])
        rescue NorthflankApi::Error => error
          snapshot.with(gaps: snapshot.gaps + [ ResourceMap::Gap.new(text: Sentence.join("Templates could not be read", error), kinds: [ ResourceMap::KIND_STACK ]) ])
        end

        private

        # A run as the list or the details give it, named by its template. Its own name and description are the
        # template's, so only the status words a person needs are its detail.
        def template_run(run, name, url) = release_run(run.except("name", "description"), name, url: url)

        # Each node that does something, as Releases#parts_of reads it, with how to read its log only where the node's
        # project is one this connection reaches. A node in any other project, or one whose project is not known yet,
        # has no log to read here.
        def template_parts(run, environment_row)
          refs = run["refs"].is_a?(Hash) ? run["refs"] : {}
          placed = placed_nodes(run["spec"], nil, refs)
          names = placed.map { |node, _project| node_name(node) }
          reached = ConnectionSettings.of(environment_row).scopes
          placed.each_with_index.map do |(node, project), index|
            name = names.count(names[index]) > 1 && node["ref"].present? ? "#{names[index]} (#{node['ref']})" : names[index]
            part = node_part(node, name, index)
            next part.with(log: nil) unless part.log && reached.include?(project)

            part.with(log: part.log.merge(History::LOG_ARGUMENTS => part.log[History::LOG_ARGUMENTS].merge(PROJECT => project)))
          end
        end

        # Each node with the project it acts in, its own projectId or else the one the workflow holding it gave as context.
        def placed_nodes(node, project, refs, found = [])
          case node
          when Array then node.each { |each| placed_nodes(each, project, refs, found) }
          when Hash
            return found unless node["kind"].is_a?(String)

            spec = node["spec"].is_a?(Hash) ? node["spec"] : {}
            here = project_named(spec["projectId"], refs) || project
            if Releases::CONTAINERS.include?(node["kind"])
              placed_nodes(spec["steps"], project_named(spec.dig("context", "projectId"), refs) || here, refs, found)
            else
              found << [ node, here ]
            end
          end
          found
        end

        def project_named(value, refs)
          return value if literal?(value)

          made = value.to_s.match(PROJECT_REFERENCE)
          id = made && refs.dig(made[1], "id")
          id if literal?(id)
        end

        def template_named(environment_row, reference)
          fail! "Say which template, by name or id." if reference.to_s.strip.empty?

          listed = reading_templates { api(environment_row).templates }
          found = Named.find(listed.items, reference, id: "id", name: "name", provider: PROVIDER, connection: environment_row)
          return found if found

          names = listed.items.filter_map { |template| template["name"].presence || template["id"] }
          fail! "No template called #{reference} in the team. #{names.any? ? "Its templates are #{names.first(NAMES_LISTED).to_sentence}." : 'It has no templates.'}" if listed.complete

          begin
            reading_templates { api(environment_row).template(reference.to_s.strip) }.presence ||
              fail!("Only the first #{listed.items.size} templates were read, and none is called #{reference}. Name it by its id.")
          rescue NorthflankApi::NotFound
            fail! "Only the first #{listed.items.size} templates were read, and none is called #{reference}. Name it by its id."
          end
        end

        def reading_templates
          yield
        rescue NorthflankApi::Forbidden => error
          fail!(Sentence.all(error, "The API token cannot read templates. #{READ_PERMISSION}"))
        end

        def changing_templates(permission)
          yield
        rescue NorthflankApi::Forbidden => error
          fail!(Sentence.all(error, permission))
        end

        # A template's runs page, or one run's, under the team the map holds this connection's resources in, so reading a
        # template never reads the project's services as well. nil before the map holds any.
        def template_runs_link(environment_row, template_id, *run)
          held = ResourceMap::Resource.present.where(integration_environment: environment_row, provider: PROVIDER_KEY)
          # A stack is kept under the team alone, and a project under team/project once a service named the team.
          team = held.where(kind: ResourceMap::KIND_STACK).pick(:account) || held.where("account LIKE '%/%'").pick(:account)&.split("/")&.first
          team_link(environment_row, team, TEMPLATES, template_id, Releases::RUNS, *run.compact_blank)
        end

        def templates_link(environment_row)
          site = ConnectionSettings.of(environment_row).site
          site.present? ? Telemetry::Link.new(provider: PROVIDER, url: "#{site.chomp('/')}/#{TEMPLATES_PAGE}") : nil
        end
      end
    end
  end
end
