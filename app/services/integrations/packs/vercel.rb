module Integrations
  module Packs
    # Vercel for one team per environment: its projects, their deployments and their build and runtime logs, read with an
    # access token the team creates in Vercel. Every tool reads, except the rollback and promotion an admin switches on
    # for Halon to apply fixes. Paths, parameters and answers are the ones in Vercel's OpenAPI spec (openapi.vercel.sh),
    # and how a rollback or promotion is asked follows Vercel's own CLI (vercel/vercel, packages/cli/src/commands).
    # Vercel's remote MCP server only accepts the AI clients Vercel has approved, so Firefight reaches its API directly.
    class Vercel < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze
      TEAM = "team".freeze

      PROVIDER = "Vercel".freeze
      PROVIDER_KEY = "vercel".freeze
      PRODUCTION = "production".freeze
      READY = "READY".freeze

      LOG_TYPES = %w[runtime build].freeze
      RUNTIME = LOG_TYPES.first
      # How long a runtime log read watches the live stream. Vercel's CLI watches for up to 5 minutes, and a tool call
      # stays far shorter.
      DEFAULT_SECONDS = 20
      MAX_SECONDS = 60
      LOG_LIMIT = 200
      DEPLOYMENT_LIMIT = 20
      LATEST_SHOWN = 5
      # How long Vercel keeps runtime logs on each plan (docs, logs/runtime, Limits).
      RETENTION = "1 hour on Hobby, 1 day on Pro, 3 days on Enterprise and 30 days with Observability Plus".freeze
      # Build events that carry a line of output (spec, getDeploymentEvents type).
      OUTPUT_EVENTS = %w[command stdout stderr fatal exit].freeze
      # Commit details Vercel keeps in a deployment's meta, by Git provider (vercel/vercel, commands/bisect/index.ts).
      COMMIT_SHA = %w[githubCommitSha gitlabCommitSha bitbucketCommitSha].freeze
      COMMIT_MESSAGE = %w[githubCommitMessage gitlabCommitMessage bitbucketCommitMessage].freeze
      COMMIT_REF = %w[githubCommitRef gitlabCommitRef bitbucketCommitRef].freeze

      RESOURCE = { "type" => "string", "description" => "A project in the team, by name or id, as list_resources shows it" }.freeze
      DEPLOYMENT = { "type" => "string", "description" => "A deployment of the project, by its id (dpl_...) or its URL, as list_deployments shows it" }.freeze

      tool :list_resources,
           description: "The projects in the Vercel team for this environment, with their framework and the state of their " \
                        "production deployment. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_resource,
           description: "How one project is set up and how it stands now: its framework, Git repository and production branch, " \
                        "the production deployment and its state, its domains, its latest deployments, and how the last " \
                        "rollback or promotion went",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :list_deployments,
           description: "A project's deployments, newest first: when, production or preview, its state and why it failed, the " \
                        "commit and branch, who made it, its page, and which one serves production now. Use it to see what " \
                        "changed before something broke, and for the id rollback_deployment and promote_deployment take",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "production_only" => { "type" => "boolean", "description" => "Only production deployments (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :deployment_logs,
           description: "Log lines of one deployment of a project. type build reads its build output, newest first, of the " \
                        "newest deployment unless one is named. type runtime watches what its functions log live, for up to #{MAX_SECONDS} " \
                        "seconds, of the production deployment unless one is named, since Vercel's API gives no past runtime " \
                        "logs. Earlier runtime logs are on the project's Logs page",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "deployment" => DEPLOYMENT.merge("description" => "#{DEPLOYMENT['description']} (optional)"),
               "type" => { "type" => "string", "enum" => LOG_TYPES, "description" => "Which logs (optional, runtime)" },
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "seconds" => { "type" => "integer", "description" => "How long to watch runtime logs, in seconds (optional, #{DEFAULT_SECONDS}, at most #{MAX_SECONDS})" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rollback_deployment,
           description: "Point a project's production domains back at an earlier production deployment, without building it " \
                        "again. Afterwards new deployments no longer go live on their own until one is promoted with " \
                        "promote_deployment. The Hobby plan can only go back to the previous production deployment",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE, "deployment" => DEPLOYMENT,
               "reason" => { "type" => "string", "description" => "Why, shown with the rollback in Vercel (optional)" }
             },
             "required" => %w[resource deployment]
           },
           read_only: false

      tool :promote_deployment,
           description: "Make a production deployment of a project serve its production domains, without building it again. " \
                        "It undoes a rollback, and lets new deployments go live on their own again",
           params_schema: {
             "type" => "object",
             "properties" => { "resource" => RESOURCE, "deployment" => DEPLOYMENT },
             "required" => %w[resource deployment]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "Access token", secret: true, placeholder: "",
                              hint: "A Vercel access token created under Account Settings, Tokens, scoped to the team. It acts with the access of the person who created it.")
        ]
      end

      # Lists one project with the token, so a wrong token or team is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token = values[API_TOKEN].to_s.strip
        return "Paste an access token." if token.empty?

        VercelApi.new(token, fields[TEAM]).check!
        nil
      rescue VercelApi::Error => error
        "Vercel refused this token or team. #{error.message}"
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_resources(environment_row:, arguments:)
        rows = projects(environment_row).map do |project|
          production = project.dig("targets", PRODUCTION)
          state = production ? "production #{production['readyState'].to_s.downcase}" : "no production deployment"
          [ "#{project['name']} (#{project['id']})", project["framework"], state, ("paused" if project["paused"]) ].compact.join(", ")
        end
        text = rows.empty? ? "This team has no projects." : "#{rows.size} projects.\n#{rows.join("\n")}"
        Telemetry.result(text, link: nil)
      end

      def describe_resource(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        detail = api(environment_row).project(project["id"])
        production = detail.dig("targets", PRODUCTION)
        domains = api(environment_row).project_domains(project["id"])
        latest = Array(detail["latestDeployments"]).first(LATEST_SHOWN)
        lines = [
          "#{detail['name']}, #{detail['framework'] || 'no framework set'}#{', paused' if detail['paused']}",
          repository_line(detail["link"]),
          (production ? "Production: #{deployment_line(production)}" : "Production: no deployment yet"),
          alias_request_line(detail["lastAliasRequest"]),
          ("Domains:\n#{domains.map { |domain| domain_words(domain) }.join("\n")}" if domains.any?),
          ("Latest deployments:\n#{latest.map { |deployment| deployment_line(deployment) }.join("\n")}" if latest.any?)
        ]
        Telemetry.result(lines.compact.join("\n"), link: project_link(environment_row, detail))
      end

      def list_deployments(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        target = PRODUCTION if ActiveModel::Type::Boolean.new.cast(arguments["production_only"])
        deployments = api(environment_row).deployments(project["id"], limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT), target: target)
        link = project_link(environment_row, project)
        return Telemetry.result("#{project['name']} has no deployments.", link: link) if deployments.empty?

        current = project.dig("targets", PRODUCTION, "id")
        rows = deployments.map { |deployment| deployment_line(deployment, current: current) }
        Telemetry.result("Latest #{rows.size} deployments of #{project['name']}, newest first. rollback_deployment and promote_deployment take an id.\n" \
                         "#{rows.join("\n")}", link: link)
      end

      def deployment_logs(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        build = arguments["type"].to_s == "build"
        # A build that failed is the newest deployment, not the one serving production.
        asked = arguments["deployment"].presence || (latest_id(environment_row, project) if build)
        deployment = find_deployment(environment_row, project, asked)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        if build
          build_logs(environment_row, project, deployment, arguments, limit)
        else
          runtime_logs(environment_row, project, deployment, arguments, limit)
        end
      end

      def rollback_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        begin
          api(environment_row).rollback(project["id"], deployment["id"], description: arguments["reason"].to_s.strip.first(250))
        rescue VercelApi::PlanLimited => error
          fail! "#{error.message}. On Vercel's Hobby plan a rollback can only go to the previous production deployment, so pick " \
                "that one from list_deployments, or roll back further on a Pro plan."
        end
        Telemetry.result("Vercel is pointing the production domains of #{project['name']} at #{deployment['id']}. New deployments no " \
                         "longer go live on their own until one is promoted, so promote the fixed deployment with " \
                         "promote_deployment when it is ready. describe_resource shows how the rollback went.",
                         link: project_link(environment_row, project))
      end

      def promote_deployment(environment_row:, arguments:)
        project = find_project(environment_row, arguments["resource"])
        deployment = find_deployment(environment_row, project, arguments["deployment"], required: true)
        unless deployment["target"] == PRODUCTION
          fail! "#{deployment['id']} is a preview deployment. Vercel promotes a preview by building it again for production, " \
                "which this tool does not do. Redeploy it to production in Vercel, then promote that deployment."
        end

        answer = api(environment_row).promote(project["id"], deployment["id"])
        done = if answer.status == 202
          "Vercel queued the promotion of #{deployment['id']} for #{project['name']}. It starts when the rolling release in progress completes."
        else
          "Vercel is pointing the production domains of #{project['name']} at #{deployment['id']}, and new production deployments go live on their own again."
        end
        Telemetry.result("#{done} describe_resource shows how the promotion went.", link: project_link(environment_row, project))
      end

      # The team's projects on the resource map, each with the repository it builds from and the verified domains it
      # serves. What could not be read for one project is a gap, not a failed sweep.
      def map_of(environment_row)
        api = api(environment_row)
        resources = []
        links = []
        gaps = []
        projects(environment_row).each do |project|
          production = project.dig("targets", PRODUCTION) || {}
          found = ResourceMap::Found.new(
            provider: PROVIDER_KEY, account: project["accountId"].to_s, kind: ResourceMap::KIND_SITE, external_id: project["id"].to_s,
            name: project["name"].presence || project["id"].to_s, status: project["paused"] ? "paused" : production["readyState"]&.downcase,
            url: project_link(environment_row, project)&.url,
            details: { "type" => project["framework"], "branch" => project.dig("link", "productionBranch"),
                       ResourceMap::DEPLOYED_COMMIT => meta(production, COMMIT_SHA) }.compact
          )
          resources << found
          repository = repository(project["link"])
          if repository
            resources << repository
            links << ResourceMap::FoundLink.new(from: found.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
          end
          begin
            api.project_domains(project["id"]).select { |domain| domain["verified"] && domain["redirect"].blank? }.each do |domain|
              host = ResourceMap.domain(domain["name"])
              resources << host
              links << ResourceMap::FoundLink.new(from: host.key, to: found.key, relation: ResourceMap::RELATION_SERVED_BY)
            end
          rescue Integrations::RateLimited
            raise
          rescue VercelApi::Error => error
            gaps << "The domains of #{project['name']} could not be read: #{error.message}"
          end
        end
        listed = project_list(environment_row)
        if listed.incomplete?
          gaps << "Only the first #{listed.items.size} projects were read."
          return ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps, unread_kinds: [ ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN ])
        end
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)
      end

      def check_health!(environment_row)
        api(environment_row).check!
      rescue VercelApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token = settings.credential(API_TOKEN)
        fail! "This environment has no Vercel access token. Reconnect it on the Integrations page." if token.blank?

        VercelApi.new(token, settings.field(TEAM))
      end

      def projects(environment_row) = project_list(environment_row).items

      # The team's projects, as a Pages::Read that says whether they were read to the end.
      def project_list(environment_row) = @project_list ||= api(environment_row).projects

      def find_project(environment_row, asked)
        fail! "Say which project, by name or id. list_resources shows them." if asked.to_s.strip.empty?

        rows = projects(environment_row).map { |project| { id: project["id"], name: project["name"], project: project } }
        Hosting.named(rows, asked)&.dig(:project) || fail!("No project called #{asked} in this team. list_resources shows what there is.")
      end

      # The deployment asked for, or the production one, checked to be the project's own.
      def find_deployment(environment_row, project, asked, required: false)
        asked = asked.to_s.strip
        fail! "Say which deployment, by the id list_deployments shows." if asked.empty? && required

        reference = asked.presence || project.dig("targets", PRODUCTION, "id")
        fail! "#{project['name']} has no production deployment. Name one from list_deployments." if reference.blank?

        deployment = api(environment_row).deployment(reference.delete_prefix("https://"))
        unless deployment["projectId"] == project["id"]
          fail! "#{asked} is not a deployment of #{project['name']}. list_deployments shows its deployments."
        end

        deployment
      end

      def latest_id(environment_row, project)
        latest = api(environment_row).deployments(project["id"], limit: 1).first
        latest && (latest["uid"] || latest["id"])
      end

      def build_logs(environment_row, project, deployment, arguments, limit)
        events = api(environment_row).deployment_events(deployment["id"], limit: limit)
        lines = events.filter_map do |event|
          payload = event["payload"].is_a?(Hash) ? event["payload"] : event
          next unless OUTPUT_EVENTS.include?(event["type"]) && payload["text"].present?

          at = millis(payload["date"] || event["created"])
          Telemetry::LogLine.new(at: at || Time.current, source: event["type"], text: payload["text"]) if wanted?(payload["text"], arguments)
        end
        error = [ deployment["errorCode"], deployment["errorMessage"] ].compact.join(": ").presence
        head = error ? "#{deployment['id']} failed: #{error}#{" (#{deployment['errorStep']})" if deployment['errorStep']}\n" : ""
        oom = deployment["oomReport"].present? ? "Vercel reports the build ran out of memory.\n" : ""
        text = Telemetry.logs_text(lines, asked: "the build of #{deployment['id']}", limit: lines.size >= limit ? lines.size : limit)
        Telemetry.result("#{head}#{oom}#{text}", link: inspector_link(deployment) || project_link(environment_row, project))
      end

      def runtime_logs(environment_row, project, deployment, arguments, limit)
        seconds = arguments["seconds"].to_i.positive? ? [ arguments["seconds"].to_i, MAX_SECONDS ].min : DEFAULT_SECONDS
        rows = api(environment_row).runtime_logs(project["id"], deployment["id"], seconds: seconds, limit: limit)
        lines = rows.filter_map do |row|
          text = [ row["level"], row["requestMethod"], row["requestPath"], row["responseStatusCode"], row["message"] ].compact.join(" ")
          next unless wanted?(text, arguments)

          Telemetry::LogLine.new(at: millis(row["timestampInMs"]) || Time.current, source: row["source"].to_s, text: text)
        end.reverse
        watched = "#{deployment['id']}, watched live for up to #{seconds} seconds"
        note = "Vercel's API gives runtime logs only as they happen, so these are the lines logged while watching. Earlier " \
               "lines are on the project's Logs page, which keeps them #{RETENTION}."
        text = Telemetry.logs_text(lines, asked: watched, limit: rows.size >= limit ? lines.size : limit + 1)
        Telemetry.result("#{text}\n#{note}", link: logs_link(environment_row, project))
      end

      def wanted?(text, arguments)
        include = arguments["text"].to_s
        exclude = arguments["exclude"].to_s
        (include.empty? || text.to_s.include?(include)) && (exclude.empty? || !text.to_s.include?(exclude))
      end

      def deployment_line(deployment, current: nil)
        id = deployment["uid"] || deployment["id"]
        sha = meta(deployment, COMMIT_SHA)
        message = meta(deployment, COMMIT_MESSAGE).to_s.lines.first.to_s.strip
        created = millis(deployment["createdAt"] || deployment["created"])&.iso8601
        error = [ deployment["errorCode"], deployment["errorMessage"] ].compact.join(": ").presence
        [ created, id, deployment["target"] || "preview", (deployment["readyState"] || deployment["state"]).to_s.downcase,
          deployment["readySubstate"]&.downcase, ("serving production now" if current && id == current),
          ("#{sha.first(12)} \"#{message}\"" if sha), ("on #{meta(deployment, COMMIT_REF)}" if meta(deployment, COMMIT_REF)),
          ("by #{deployment.dig('creator', 'username')}" if deployment.dig("creator", "username")),
          ("failed: #{error}" if error), ("ran out of memory" if deployment["oomReport"].present?),
          ("page #{deployment['inspectorUrl']}" if deployment["inspectorUrl"]) ].compact.join(", ")
      end

      def alias_request_line(request)
        return nil unless request.is_a?(Hash)

        at = millis(request["requestedAt"])&.iso8601
        "Last #{request['type']}: to #{request['toDeploymentId']} from #{request['fromDeploymentId']}, #{request['jobStatus']}#{", asked #{at}" if at}" \
          "#{'. New deployments do not go live on their own until one is promoted' if request['type'] == 'rollback'}"
      end

      def repository_line(link)
        return "Git: not connected" unless link.is_a?(Hash)

        repository = link["repo"] ? "#{link['org']}/#{link['repo']}" : link["projectNameWithNamespace"] || link["slug"]
        "Git: #{link['type']} #{repository}, production branch #{link['productionBranch'] || 'unknown'}"
      end

      def domain_words(domain)
        [ domain["name"], ("redirects to #{domain['redirect']}" if domain["redirect"].present?), ("branch #{domain['gitBranch']}" if domain["gitBranch"]),
          ("not verified" unless domain["verified"]) ].compact.join(", ")
      end

      # The repository a project builds from. Vercel's link types are the registry's keys of the code hosts it links to.
      def repository(link)
        return nil unless link.is_a?(Hash) && link["org"].present? && link["repo"].present?

        ResourceMap.repository(link["type"], "#{link['org']}/#{link['repo']}")
      end

      def meta(deployment, keys) = keys.filter_map { |key| deployment.to_h.dig("meta", key).presence }.first

      def millis(value) = value.is_a?(Numeric) ? Time.zone.at(value / 1000.0).utc : Telemetry.parse_time(value)

      def inspector_link(deployment) = deployment["inspectorUrl"].present? ? Telemetry::Link.new(provider: PROVIDER, url: deployment["inspectorUrl"]) : nil

      # A project's page, https://vercel.com/<team slug>/<project name>, as Vercel's CLI opens it (commands/open/index.ts).
      # Without a known slug there is no page to name.
      def project_link(environment_row, project)
        slug = owner_slug(environment_row)
        slug ? Telemetry::Link.new(provider: PROVIDER, url: "#{ConnectionSettings.of(environment_row).site}/#{ERB::Util.url_encode(slug)}/#{ERB::Util.url_encode(project['name'])}") : nil
      end

      # The project's Logs page, the address Vercel's docs open as /[team]/[project]/logs (docs, logs/runtime).
      def logs_link(environment_row, project)
        page = project_link(environment_row, project)
        page && Telemetry::Link.new(provider: "#{PROVIDER}, on the Logs page", url: "#{page.url}/logs")
      end

      # The slug the dashboard uses: the team's, read from Vercel when the team is given by id, or the person's username
      # for a personal account. nil when Vercel will not say.
      def owner_slug(environment_row)
        return @owner_slug if defined?(@owner_slug)

        team = ConnectionSettings.of(environment_row).field(TEAM).to_s.strip
        @owner_slug = if team.match?(VercelApi::TEAM_ID) then api(environment_row).team(team)["slug"].presence
        elsif team.present? then team
        else api(environment_row).user["username"].presence
        end
      rescue Integrations::RateLimited
        raise
      rescue VercelApi::Error
        @owner_slug = nil
      end
    end
  end
end
