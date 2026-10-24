module Integrations
  module Packs
    # What PlanetScale's MCP server has no tool for, read and changed through PlanetScale's own API with the connection's
    # credentials, beside the server's tools on the same connection: deploy requests with their deployment and each schema
    # change it makes, the changes made to a branch's size and settings, and the changes to a deploy request's run, a
    # branch's size and which branch is production. Paths, parameters and fields are the ones PlanetScale's OpenAPI
    # description gives (api.planetscale.com/v1/openapi-spec). A connection signed in to PlanetScale holds an OAuth
    # access token, which the API takes as Bearer. One made with a service token holds only its secret, which the server
    # takes alone, while the API takes the token's id beside it (planetscale.com/docs/api/reference/service-tokens), so
    # such a connection names the id in its connect field.
    class Planetscale < NativePack
      PROVIDER = MapReaders::Planetscale::NAME
      PROVIDER_KEY = MapReaders::Planetscale::PROVIDER
      # What a service token's secret starts with (planetscale.com/docs/mcp/service-token).
      SERVICE_TOKEN = "pscale_tkn_".freeze
      TOKEN_ID = "service_token_id".freeze
      NEEDS_TOKEN_ID = "This PlanetScale connection was made with a service token, and PlanetScale's API takes the token's id beside " \
                       "its secret. On Integrations, open PlanetScale's details and choose Add beside Service token ID to give it the id, or sign in to " \
                       "PlanetScale instead, so Firefight can reach it.".freeze
      POSTGRES = MapReaders::Planetscale::POSTGRES
      DEPLOY_LIMIT = 20
      DEPLOY_MOST = 100
      OPERATION_LIMIT = 50
      CANCEL = "planetscale_cancel_deploy_request".freeze

      ORGANIZATION = { "type" => "string", "description" => "The organization, by its name as planetscale_list_organizations gives it" }.freeze
      DATABASE = { "type" => "string", "description" => "The database, by its name" }.freeze
      BRANCH = { "type" => "string", "description" => "The branch, by its name, such as main" }.freeze
      NUMBER = { "type" => "integer", "description" => "The deploy request's number, as planetscale_list_deploy_requests gives it" }.freeze
      DEPLOY_REQUEST = { "type" => "object", "properties" => { "organization" => ORGANIZATION, "database" => DATABASE, "number" => NUMBER },
                         "required" => %w[organization database number] }.freeze
      ON_BRANCH = { "type" => "object", "properties" => { "organization" => ORGANIZATION, "database" => DATABASE, "branch" => BRANCH },
                    "required" => %w[organization database branch] }.freeze

      tool :planetscale_list_deploy_requests,
           summary: "Lists a database's deploy requests with their state and how long each deploy took.",
           description: "A database's deploy requests, newest first, each with its number, the branch it deploys and the one it deploys " \
                        "into, whether it is open, how its deployment stands (queued, in progress, waiting for cutover, complete, reverted, " \
                        "errored), who opened it, when it started and finished, and its page in PlanetScale. Deploy requests are how " \
                        "schema changes reach a Vitess database, so use it to see what changed a schema before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "organization" => ORGANIZATION, "database" => DATABASE,
               "into_branch" => { "type" => "string", "description" => "Only deploy requests into this branch, such as main (optional)" },
               "state" => { "type" => "string", "enum" => %w[open closed deployed], "description" => "Only open, closed or deployed ones (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => %w[organization database]
           },
           read_only: true

      tool :planetscale_get_deploy_request,
           summary: "Shows one deploy request with each schema change it makes and any deploy error.",
           description: "One deploy request in full: how its deployment stands and when it was queued, started, ready to cut over and " \
                        "finished, every schema change it makes (the table, the DDL, its state, progress and the error PlanetScale gave " \
                        "when it failed), the lint errors that stop it, whether it waits for a cutover, and whether its revert window " \
                        "is still open. Use it to see why a deploy failed or what it is waiting for",
           params_schema: DEPLOY_REQUEST,
           read_only: true

      tool :planetscale_list_branch_changes,
           summary: "Lists the changes made to a branch's size, replicas, storage and settings.",
           description: "The changes made to a branch's cluster, newest first, each with its state, when it started and finished, " \
                        "who made it and what it changed from and to. A Postgres branch's are its cluster size, replicas, storage and " \
                        "parameters. A Vitess branch's are its VTGate resizes and configuration changes, and with a keyspace that " \
                        "keyspace's resizes",
           params_schema: {
             "type" => "object",
             "properties" => {
               "organization" => ORGANIZATION, "database" => DATABASE, "branch" => BRANCH,
               "keyspace" => { "type" => "string", "description" => "A Vitess keyspace whose resizes to read too (optional)" }
             },
             "required" => %w[organization database branch]
           },
           read_only: true

      tool :planetscale_revert_deploy_request,
           summary: "Reverts a deployed schema change while its revert window is open.",
           description: "Put a database's schema back as it was before a deploy request, while PlanetScale still keeps its revert " \
                        "window open, which planetscale_get_deploy_request says",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool CANCEL,
           summary: "Takes a queued deploy request out of the deploy queue.",
           description: "Cancel a deploy request waiting in the deploy queue, so it does not change the schema. It can be queued again later",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool :planetscale_skip_revert_period,
           summary: "Ends a deployed schema change's revert window now.",
           description: "Close the revert window of a deploy request that deployed, so it can no longer be reverted, which lets the " \
                        "next deploy into the branch start",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool :planetscale_force_cutover,
           summary: "Cuts a waiting deploy request over to its new schema now.",
           description: "Cut over a deploy request that has copied its changes and waits for the cutover, now rather than when " \
                        "PlanetScale would",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool :planetscale_apply_deploy_request,
           summary: "Applies a gated deploy request that waits to be applied.",
           description: "Apply the changes of a deploy request made with gated deployments, once they are ready, so the schema " \
                        "changes take effect",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool :planetscale_complete_errored_deploy,
           summary: "Completes a deploy request that errored, keeping the changes that applied.",
           description: "Mark a deploy request whose deployment errored as complete, keeping the schema changes that applied and " \
                        "leaving out the ones that failed",
           params_schema: DEPLOY_REQUEST,
           read_only: false

      tool :planetscale_resize_branch,
           summary: "Changes a branch's cluster size or replicas, or a Vitess keyspace's or VTGates' size.",
           description: "Change the size of a branch. A Postgres branch takes cluster_size (as planetscale_list_cluster_sizes names " \
                        "them) and replicas, its total count. A Vitess database is sized per keyspace, so name the keyspace with its " \
                        "cluster_size and extra_replicas, or change the branch's VTGates with vtgate_size and vtgate_count. A change " \
                        "PlanetScale has not started yet replaces one asked before",
           params_schema: {
             "type" => "object",
             "properties" => {
               "organization" => ORGANIZATION, "database" => DATABASE, "branch" => BRANCH,
               "cluster_size" => { "type" => "string", "description" => "The cluster size to run at, such as PS_80 (optional)" },
               "replicas" => { "type" => "integer", "description" => "Postgres only: how many replicas in all (optional)" },
               "keyspace" => { "type" => "string", "description" => "Vitess only: the keyspace to resize (optional)" },
               "extra_replicas" => { "type" => "integer", "description" => "Vitess keyspace only: replicas beyond the ones included (optional)" },
               "vtgate_size" => { "type" => "string", "description" => "Vitess only: the VTGate size, such as VTG_10 (optional)" },
               "vtgate_count" => { "type" => "integer", "description" => "Vitess only: VTGates in each availability zone (optional)" }
             },
             "required" => %w[organization database branch]
           },
           read_only: false

      tool :planetscale_promote_branch,
           summary: "Makes a development branch a production branch.",
           description: "Promote a development branch to a production branch",
           params_schema: ON_BRANCH,
           read_only: false

      tool :planetscale_demote_branch,
           summary: "Makes a production branch a development branch again.",
           description: "Demote a production branch to a development branch",
           params_schema: ON_BRANCH,
           read_only: false

      def self.beside_server? = true

      # Whether the connection's credentials reach PlanetScale's API, as a sign-in does, and a service token with its id.
      def self.reaches_api?(environment_row) = Credentials.signed_in?(environment_row) || ConnectionSettings.of(environment_row).field(TOKEN_ID).present?

      def self.api(environment_row) = PlanetscaleApi.new(authorization(environment_row))

      # The Authorization header PlanetScale's API takes for this connection, from the credentials the server is reached
      # with: an OAuth access token as it is, or a service token's secret with the id the connect form asked.
      def self.authorization(environment_row)
        given = Credentials.headers_for(environment_row)["Authorization"].to_s.strip
        token = given.sub(/\ABearer\s+/i, "")
        raise NativePack::Error, "This PlanetScale connection holds no credentials to reach PlanetScale's API." if token.empty?
        return given unless token.start_with?(SERVICE_TOKEN)

        id = ConnectionSettings.of(environment_row).field(TOKEN_ID).to_s.strip
        raise NativePack::Error, NEEDS_TOKEN_ID if id.empty?

        "#{id}:#{token}"
      end

      # How a deploy request's deployment stands (Deployment state), in Firefight's words. One opened and not deployed yet
      # is queued, one reverted is no longer what the branch runs, and one with nothing to change never ran.
      DEPLOY_STATES = {
        "pending" => Capabilities::History::QUEUED, "ready" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED,
        "submitting" => Capabilities::History::QUEUED, "in_progress" => Capabilities::History::RUNNING,
        "pending_cutover" => Capabilities::History::RUNNING, "in_progress_vschema" => Capabilities::History::RUNNING,
        "in_progress_cancel" => Capabilities::History::RUNNING, "in_progress_cutover" => Capabilities::History::RUNNING,
        "in_progress_revert" => Capabilities::History::RUNNING, "in_progress_revert_vschema" => Capabilities::History::RUNNING,
        "complete" => Capabilities::History::SUCCEEDED, "complete_pending_revert" => Capabilities::History::SUCCEEDED,
        "complete_revert" => Capabilities::History::CANCELLED, "complete_cancel" => Capabilities::History::CANCELLED,
        "cancelled" => Capabilities::History::CANCELLED, "no_changes" => Capabilities::History::CANCELLED,
        "complete_error" => Capabilities::History::FAILED, "complete_revert_error" => Capabilities::History::FAILED,
        "error" => Capabilities::History::FAILED
      }.freeze
      # A deploy operation's state (List deploy operations).
      OPERATION_STATES = {
        "pending" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED, "in_progress" => Capabilities::History::RUNNING,
        "complete" => Capabilities::History::SUCCEEDED, "cancelled" => Capabilities::History::CANCELLED, "error" => Capabilities::History::FAILED
      }.freeze
      # A branch change's state (branch change, resize and config change requests).
      CHANGE_STATES = {
        "draft" => Capabilities::History::QUEUED, "pending" => Capabilities::History::QUEUED, "queued" => Capabilities::History::QUEUED,
        "resizing" => Capabilities::History::RUNNING, "applying" => Capabilities::History::RUNNING, "completed" => Capabilities::History::SUCCEEDED,
        "canceled" => Capabilities::History::CANCELLED, "failed" => Capabilities::History::FAILED
      }.freeze
      DEPLOY_REQUEST_KIND = "deploy request".freeze
      CHANGE_KIND = "branch change".freeze
      RESIZE_KIND = "resize".freeze
      CONFIG_KIND = "config change".freeze
      CLOSED = "closed".freeze

      def planetscale_list_deploy_requests(environment_row:, arguments:)
        organization, database = place(arguments)
        limit = Capabilities::Answers.limit(arguments, DEPLOY_MOST, default: DEPLOY_LIMIT)
        listed = api(environment_row).deploy_requests(organization, database, into_branch: arguments["into_branch"], state: arguments["state"], per_page: limit)
        into = arguments["into_branch"].present? ? " into #{arguments['into_branch']}" : ""
        link = database_link(environment_row, organization, database)
        if listed.empty?
          result = Telemetry.result("#{database} has no deploy requests#{into} that match.", link: link)
          return Capabilities::Deploys.with_deploys(Capabilities::RunHistory.with_runs(result, [], link: link), [])
        end

        rows = listed.first(limit).map { |request| request_line(request) }
        result = Telemetry.result("Latest #{rows.size} deploy requests of #{database}#{into}, newest first. planetscale_get_deploy_request " \
                                  "reads one with its schema changes, and rollback takes its number.\n#{rows.join("\n")}", link: link)
        runs = listed.first(limit).map { |request| run_of(request) }
        Capabilities::Deploys.with_deploys(Capabilities::RunHistory.with_runs(result, runs, link: link), listed.first(limit).map { |request| deploy_of(request) })
      end

      def planetscale_get_deploy_request(environment_row:, arguments:)
        organization, database = place(arguments)
        number = number!(arguments)
        request = api(environment_row).deploy_request(organization, database, number)
        operations = api(environment_row).deploy_operations(organization, database, number)
        deployment = request["deployment"].is_a?(Hash) ? request["deployment"] : {}
        lines = [ "Deploy request ##{number} of #{database}: #{request['branch']} into #{request['into_branch']}, #{request['state']}, " \
                  "deployment #{request['deployment_state']}#{', approved' if request['approved']}",
                  ("Opened by #{request.dig('actor', 'display_name')}" if request.dig("actor", "display_name")),
                  timeline(request, deployment), *waiting(deployment), *lint(deployment), *operation_lines(operations) ]
        run = run_of(request, parts: operations.map { |operation| part_of(operation) })
        Capabilities::RunHistory.with_runs(Telemetry.result(lines.compact.join("\n"), link: request_link(request)), [ run ], link: request_link(request))
      rescue PlanetscaleApi::NotFound
        fail!("#{database} has no deploy request ##{number}.")
      end

      def planetscale_list_branch_changes(environment_row:, arguments:)
        organization, database = place(arguments)
        branch = required!(arguments, "branch")
        client = api(environment_row)
        changes = if postgres?(client, organization, database)
          client.branch_changes(organization, database, branch).map { |change| change_run(change, CHANGE_KIND, postgres_change(change)) }
        else
          keyspace = arguments["keyspace"].to_s.strip.presence
          client.branch_resizes(organization, database, branch).map { |change| change_run(change, RESIZE_KIND, vtgate_change(change)) } +
            client.branch_config_changes(organization, database, branch).map { |change| change_run(change, CONFIG_KIND, config_change(change)) } +
            (keyspace ? client.keyspace_resizes(organization, database, branch, keyspace).map { |change| change_run(change, "#{keyspace} #{RESIZE_KIND}", keyspace_change(change)) } : [])
        end
        runs = changes.sort_by { |run| run.started_at || Time.zone.at(0) }.reverse
        link = branch_link(environment_row, organization, database, branch)
        text = if runs.empty?
          "No changes have been made to #{database}/#{branch}'s size or settings."
        else
          "#{runs.size} changes to #{database}/#{branch}, newest first.\n#{runs.map { |run| Capabilities::History.line(run) }.join("\n")}"
        end
        Capabilities::RunHistory.with_runs(Telemetry.result(text, link: link), runs, link: link)
      end

      def planetscale_revert_deploy_request(environment_row:, arguments:)
        act(environment_row, arguments, "revert", "is reverting deploy request #%<number>s. Its status says when the schema is back.")
      end

      def planetscale_cancel_deploy_request(environment_row:, arguments:)
        act(environment_row, arguments, "cancel", "cancelled deploy request #%<number>s, so it does not change the schema. It can be deployed again.")
      end

      def planetscale_skip_revert_period(environment_row:, arguments:)
        act(environment_row, arguments, "skip-revert", "closed the revert window of deploy request #%<number>s, so it can no longer be reverted.")
      end

      def planetscale_force_cutover(environment_row:, arguments:)
        act(environment_row, arguments, "force-cutover", "is cutting deploy request #%<number>s over now.")
      end

      def planetscale_apply_deploy_request(environment_row:, arguments:)
        act(environment_row, arguments, "apply-deploy", "is applying deploy request #%<number>s.")
      end

      def planetscale_complete_errored_deploy(environment_row:, arguments:)
        act(environment_row, arguments, "complete-deploy", "marked deploy request #%<number>s complete with the schema changes that applied.")
      end

      def planetscale_resize_branch(environment_row:, arguments:)
        organization, database = place(arguments)
        branch = required!(arguments, "branch")
        client = api(environment_row)
        asked = arguments.slice("cluster_size", "replicas", "keyspace", "extra_replicas", "vtgate_size", "vtgate_count").compact_blank
        answer = if postgres?(client, organization, database)
          refuse_vitess_only!(asked)
          body = asked.slice("cluster_size", "replicas")
          fail!("Say the cluster_size or the replicas to run #{database}/#{branch} with.") if body.empty?
          client.change_branch(organization, database, branch, body)
        elsif asked["keyspace"]
          body = asked.slice("cluster_size", "extra_replicas")
          fail!("Say the cluster_size or the extra_replicas to run keyspace #{asked['keyspace']} with.") if body.empty?
          client.resize_keyspace(organization, database, branch, asked["keyspace"], body)
        else
          body = asked.slice("vtgate_size", "vtgate_count")
          fail!("#{database} is a Vitess database, sized per keyspace. Name the keyspace with its cluster_size or extra_replicas, or give vtgate_size or vtgate_count.") if body.empty?
          client.resize_vtgates(organization, database, branch, body)
        end
        state = answer.is_a?(Hash) ? answer["state"] : nil
        Telemetry.result("PlanetScale took the change to #{database}/#{branch}#{" (#{state})" if state}. planetscale_list_branch_changes " \
                         "says when it is done.", link: branch_link(environment_row, organization, database, branch))
      end

      def planetscale_promote_branch(environment_row:, arguments:)
        organization, database = place(arguments)
        branch = required!(arguments, "branch")
        api(environment_row).promote(organization, database, branch)
        Telemetry.result("#{database}/#{branch} is now a production branch. planetscale_demote_branch makes it a development branch again.",
                         link: branch_link(environment_row, organization, database, branch))
      end

      def planetscale_demote_branch(environment_row:, arguments:)
        organization, database = place(arguments)
        branch = required!(arguments, "branch")
        api(environment_row).demote(organization, database, branch)
        Telemetry.result("#{database}/#{branch} is now a development branch. planetscale_promote_branch makes it production again.",
                         link: branch_link(environment_row, organization, database, branch))
      end

      # Whoever opened the deploy request a cancel would stop. PlanetScale names them and gives no address.
      def owner_of(tool_name, environment_row:, arguments:)
        return unless tool_name == CANCEL

        organization, database = place(arguments)
        request = api(environment_row).deploy_request(organization, database, number!(arguments))
        name = request.dig("actor", "display_name").presence
        name && Owner.new(name: name, role: Owner::ROLE_CREATED, what: "deploy request ##{request['number']} of #{database}")
      end

      # Any refusal is said in PlanetScale's words, with what the connection lacks when that is why.
      def call(...)
        super
      rescue PlanetscaleApi::Refused => error
        fail!(Sentence.all(error.message, "The connection's token may lack the access this needs, which its owner grants in PlanetScale."))
      rescue PlanetscaleApi::Error => error
        fail!(error.message)
      end

      private

      def api(environment_row) = self.class.api(environment_row)

      def place(arguments) = [ required!(arguments, "organization"), required!(arguments, "database") ]

      def required!(arguments, key) = arguments[key].to_s.strip.presence || fail!("Name the #{key}.")

      def number!(arguments)
        number = Integer(arguments["number"].to_s.strip.delete_prefix("#"), exception: false)
        number&.positive? ? number : fail!("Name the deploy request by its number, as planetscale_list_deploy_requests gives it.")
      end

      def postgres?(client, organization, database) = client.database(organization, database)["kind"] == POSTGRES

      def refuse_vitess_only!(asked)
        vitess = asked.keys & %w[keyspace extra_replicas vtgate_size vtgate_count]
        fail!("#{vitess.join(', ')} only size a Vitess database. A Postgres branch takes cluster_size and replicas.") if vitess.any?
      end

      def act(environment_row, arguments, action, said)
        organization, database = place(arguments)
        number = number!(arguments)
        request = api(environment_row).act_on_deploy_request(organization, database, number, action)
        state = request.is_a?(Hash) ? request["deployment_state"] : nil
        Telemetry.result("PlanetScale #{format(said, number: number)}#{" Its deployment is #{state} now." if state}",
                         link: request_link(request) || database_link(environment_row, organization, database))
      end

      def request_line(request)
        deployment = request["deployment"].is_a?(Hash) ? request["deployment"] : {}
        [ "##{request['number']} #{request['branch']} into #{request['into_branch']}", request["state"], "deployment #{request['deployment_state']}",
          ("by #{request.dig('actor', 'display_name')}" if request.dig("actor", "display_name")), ("opened #{request['created_at']}" if request["created_at"]),
          ("deployed #{request['deployed_at']}" if request["deployed_at"]), ("finished #{deployment['finished_at']}" if deployment["finished_at"]),
          request["html_url"] ].compact.join(", ")
      end

      def timeline(request, deployment)
        stamps = { "opened" => request["created_at"], "queued" => deployment["queued_at"], "started" => deployment["started_at"],
                   "ready to cut over" => deployment["ready_to_cutover_at"], "cut over" => deployment["cutover_at"],
                   "finished" => deployment["finished_at"], "deployed" => request["deployed_at"], "closed" => request["closed_at"] }.compact_blank
        stamps.any? ? stamps.map { |what, at| "#{what} #{at}" }.join(", ").upcase_first : nil
      end

      def waiting(deployment)
        [ ("Waiting for a cutover, which planetscale_force_cutover starts now" if deployment["state"] == "pending_cutover"),
          ("The revert window is open, so planetscale_revert_deploy_request puts the schema back" if deployment["state"] == "complete_pending_revert"),
          ("The deploy queue for this branch is paused: #{deployment['queue_pause_reason'].presence || 'PlanetScale gave no reason'}" if deployment["queue_paused"]),
          ("Table #{deployment['locked_table_name']} is locked by this deployment" if deployment["table_locked"]),
          ("Deploy check errors: #{deployment['deploy_check_errors']}" if deployment["deploy_check_errors"].present?) ].compact
      end

      def lint(deployment)
        Array(deployment["lint_errors"]).first(10).map do |error|
          said = error.is_a?(Hash) ? error.values_at("lint_error", "error_description", "table_name", "column_name").compact_blank.join(", ") : error.to_s
          "Lint error: #{said.presence || error.to_json}"
        end
      end

      def operation_lines(operations)
        return [ "No schema changes are listed for it yet." ] if operations.empty?

        shown = operations.first(OPERATION_LIMIT).map do |operation|
          progress = operation["progress_percentage"].present? ? ", #{operation['progress_percentage'].round}% done" : ""
          error = operation["deploy_errors"].present? ? ", error: #{operation['deploy_errors']}" : ""
          "- #{operation_name(operation)}: #{operation['state']}#{progress}#{error}#{" (#{operation['ddl_statement'].to_s.squish.truncate(300)})" if operation['ddl_statement'].present?}"
        end
        more = operations.size > OPERATION_LIMIT ? [ "#{operations.size - OPERATION_LIMIT} more schema changes are not shown." ] : []
        [ "#{operations.size} schema changes:", *shown, *more ]
      end

      def operation_name(operation)
        table = [ operation["keyspace_name"], operation["table_name"] ].compact_blank.join(".")
        [ operation["operation_name"], table ].compact_blank.join(" ")
      end

      def run_of(request, parts: nil)
        deployment = request["deployment"].is_a?(Hash) ? request["deployment"] : {}
        status = Capabilities::History.status(request["deployment_state"], DEPLOY_STATES)
        status = Capabilities::History::CANCELLED if request["state"] == CLOSED && status == Capabilities::History::QUEUED
        finished = Capabilities::History::FINISHED.include?(status) ? (deployment["finished_at"].presence || request["deployed_at"].presence || request["closed_at"]) : nil
        Capabilities::History::Run.new(
          id: request["number"].to_s, number: request["number"], name: DEPLOY_REQUEST_KIND, status: status,
          started_at: Capabilities::RunHistory.time(deployment["started_at"].presence || deployment["queued_at"].presence || request["created_at"]),
          finished_at: Capabilities::RunHistory.time(finished), url: request["html_url"], title: request["branch"],
          detail: [ "#{request['branch']} into #{request['into_branch']}", request["deployment_state"] ].compact.join(", "), parts: parts
        )
      end

      def part_of(operation)
        status = Capabilities::History.status(operation["state"], OPERATION_STATES)
        Capabilities::History::Part.new(
          id: operation["id"], name: operation_name(operation), status: status, started_at: Capabilities::RunHistory.time(operation["created_at"]),
          finished_at: (Capabilities::RunHistory.time(operation["updated_at"]) if Capabilities::History::FINISHED.include?(status)),
          url: operation["deploy_error_docs_url"].presence, detail: operation["deploy_errors"].presence
        )
      end

      def deploy_of(request)
        run = run_of(request)
        Capabilities::Deploys::Deploy.new(id: request["number"], branch: request["branch"], version: request["number"], status: run.status,
                                          started_at: run.started_at, finished_at: run.finished_at)
      end

      def change_run(change, kind, detail)
        status = Capabilities::History.status(change["state"], CHANGE_STATES)
        by = change.dig("actor", "display_name")
        Capabilities::History::Run.new(
          id: change["id"], name: kind, status: status, started_at: Capabilities::RunHistory.time(change["started_at"].presence || change["created_at"]),
          finished_at: Capabilities::RunHistory.time(change["completed_at"]),
          detail: [ detail, change["error_message"].presence, ("by #{by}" if by) ].compact_blank.join(", ")
        )
      end

      def postgres_change(change)
        [ moved("cluster", change["previous_cluster_display_name"] || change["previous_cluster_name"], change["cluster_display_name"] || change["cluster_name"]),
          moved("replicas", change["previous_replicas"], change["replicas"]), moved("Postgres", change["previous_version"], change["version"]),
          moved("storage at most", change["previous_maximum_storage_bytes"], change["maximum_storage_bytes"]) ].compact.join(", ")
      end

      def vtgate_change(change)
        [ moved("VTGates", change["previous_vtgate_display_name"] || change["previous_vtgate_name"], change["vtgate_display_name"] || change["vtgate_name"]),
          moved("VTGate count", change["previous_vtgate_count"], change["vtgate_count"]) ].compact.join(", ")
      end

      def config_change(change)
        [ change["change_type"], change["keyspace_name"], moved("options", change["previous_options"]&.to_json, change["new_options"]&.to_json) ].compact_blank.join(", ")
      end

      def keyspace_change(change)
        [ moved("cluster", change["previous_cluster_display_name"] || change["previous_cluster_name"], change["cluster_display_name"] || change["cluster_name"]),
          moved("replicas", change["previous_replicas"], change["replicas"]) ].compact.join(", ")
      end

      def moved(what, from, to)
        return if to.nil? || from == to

        from.nil? ? "#{what} #{to}" : "#{what} #{from} to #{to}"
      end

      def request_link(request)
        url = request.is_a?(Hash) ? request["html_url"].presence : nil
        url && Telemetry::Link.new(provider: PROVIDER, url: url)
      end

      def database_link(environment_row, organization, database)
        url = ResourceMap::Resource.page_of(ConnectionSettings.of(environment_row).workspace, provider: PROVIDER_KEY, account: organization,
                                            places: [ [ ResourceMap::KIND_DATABASE, database ] ])
        url && Telemetry::Link.new(provider: PROVIDER, url: url)
      end

      def branch_link(environment_row, organization, database, branch)
        url = ResourceMap::Resource.page_of(ConnectionSettings.of(environment_row).workspace, provider: PROVIDER_KEY, account: organization,
                                            places: [ [ ResourceMap::KIND_BRANCH, "#{database}/#{branch}" ], [ ResourceMap::KIND_DATABASE, database ] ])
        url && Telemetry::Link.new(provider: PROVIDER, url: url)
      end
    end
  end
end
