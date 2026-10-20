module Integrations
  module Packs
    class Render < NativePack
      # The changes beside restart, rollback and scale, each an endpoint of Render's OpenAPI spec: cancelling a deploy
      # still in progress (POST /services/{serviceId}/deploys/{deployId}/cancel), starting a deploy (POST
      # /services/{serviceId}/deploys), suspending or resuming a service or datastore (POST .../suspend and .../resume),
      # turning autodeploy off or on (PATCH /services/{serviceId}, autoDeployTrigger) and changing autoscaling (PUT
      # /services/{serviceId}/autoscaling).
      module Controls
        CANCEL_DEPLOY = "cancel_deploy".freeze
        TRIGGER_DEPLOY = "trigger_deploy".freeze
        SUSPEND = "suspend_service".freeze
        RESUME = "resume_service".freeze
        SET_AUTODEPLOY = "set_autodeploy".freeze
        SET_AUTOSCALING = "set_autoscaling".freeze
        # When Render deploys a service on its own (spec, autoDeployTrigger): each commit to its branch, each commit once
        # its checks pass, or never. The answer names the one before as a fact, which its undo sets again.
        AUTODEPLOY_TRIGGERS = %w[commit checksPass off].freeze
        AUTODEPLOY_OFF = "off".freeze
        BEFORE = "before".freeze
        AUTODEPLOY_WORDS = { "commit" => "on each commit", "checksPass" => "on each commit once its checks pass", "off" => "off" }.freeze
        # A criterion's target is a percentage of what the plan allows.
        PERCENT = (1..100)
        # Render requires a percentage on each criterion, one switched off included, where it is not used. A criterion never
        # set before is sent switched off with this one.
        UNUSED_PERCENT = 70
        History = Capabilities::History
        # Render cancels and starts deploys of every service but a workflow, and cancels none of a cron job's (spec, Cancel
        # deploy, "Not supported for cron jobs"). A cron job deploys only its branch's latest commit (spec, commitId).
        DEPLOYING = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, CRON_JOB, STATIC_SITE ].freeze
        CANCELLABLE = DEPLOYING - [ CRON_JOB ]
        # The deployMode that deploys the last build that succeeded without building again (spec, DeployMode), and whether
        # to clear the build cache first (spec, clearCache).
        DEPLOY_ONLY = "deploy_only".freeze
        CLEAR_CACHE = "clear".freeze
        # Where each kind of resource is suspended and resumed (RenderApi::SUSPENDABLE).
        SUSPENDABLE = { POSTGRES => :postgres, KEY_VALUE => :key_value }.freeze
        DEPLOY = { "type" => "string", "description" => "The deploy, by its id, such as dep-..., as list_deployments or deploy_history shows it" }.freeze

        def self.included(pack)
          pack.tool CANCEL_DEPLOY,
                    summary: "Cancels a deploy of a service that is still building or going live.",
                    description: "Cancel a Render deploy that is still building or going live, by its id. The deploy that was live " \
                                 "before it keeps serving. A cron job's deploys cannot be cancelled",
                    params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE, "deploy" => DEPLOY }, "required" => %w[resource deploy] },
                    read_only: false

          pack.tool TRIGGER_DEPLOY,
                    summary: "Starts a new deploy of a service, of a commit, an image or its last build.",
                    description: "Start a deploy of a Render service, static site or cron job. With nothing else it builds and deploys " \
                                 "the latest commit of its branch. commit deploys one commit, image one tag of the image it runs, " \
                                 "clear_cache clears the build cache first, and deploy_only deploys the last build that succeeded again " \
                                 "without building. Autodeploy stays as it is. Follow it with deploy_history",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "commit" => { "type" => "string", "description" => "The commit to deploy, by its SHA (optional, not for a cron job)" },
                        "image" => { "type" => "string", "description" => "The image to deploy, by its full address with the tag, for a service that runs an image (optional)" },
                        "clear_cache" => { "type" => "boolean", "description" => "Clear the build cache before building (optional)" },
                        "deploy_only" => { "type" => "boolean", "description" => "Deploy the last build that succeeded again, without building (optional)" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: false

          pack.tool SET_AUTODEPLOY,
                    summary: "Turns a service's autodeploy off or on.",
                    description: "Set when Render deploys a service on its own: commit deploys each commit to its branch, checksPass " \
                                 "each commit once its checks pass, and off never. Turn it off after a rollback so the next commit does " \
                                 "not deploy the bad code again, and back on once the fix is in",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "trigger" => { "type" => "string", "enum" => AUTODEPLOY_TRIGGERS, "description" => "When to deploy on its own, off to stop it" }
                      },
                      "required" => %w[resource trigger]
                    },
                    read_only: false

          pack.tool SET_AUTOSCALING,
                    summary: "Changes a service's autoscaling: on or off, its instance range and targets.",
                    description: "Change the autoscaling of a Render web service, private service or background worker: turn it on or " \
                                 "off, the fewest and most instances, and the CPU and memory use it aims for, each a percentage of the " \
                                 "plan. What is left out stays as it is. While autoscaling is on, Render ignores a set number of instances",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "enabled" => { "type" => "boolean", "description" => "Autoscaling on or off (optional, as it is)" },
                        "min" => { "type" => "integer", "description" => "The fewest instances (optional, as it is)" },
                        "max" => { "type" => "integer", "description" => "The most instances (optional, as it is)" },
                        "cpu_percent" => { "type" => "integer", "description" => "The average CPU use to aim for, 1 to 100, or 0 to stop scaling on CPU (optional, as it is)" },
                        "memory_percent" => { "type" => "integer", "description" => "The average memory use to aim for, 1 to 100, or 0 to stop scaling on memory (optional, as it is)" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: false

          pack.tool SUSPEND,
                    summary: "Suspends a service or datastore, which stops it until it is resumed.",
                    description: "Suspend a Render service, Postgres database or Key Value instance. It stops running and serving until " \
                                 "resume_service brings it back",
                    params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
                    read_only: false

          pack.tool RESUME,
                    summary: "Resumes a suspended service or datastore.",
                    description: "Resume a suspended Render service, Postgres database or Key Value instance. A service starts again on " \
                                 "its last deploy",
                    params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
                    read_only: false
        end

        def cancel_deploy(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless CANCELLABLE.include?(resource[:type])
            fail! "Render cancels deploys of web services, private services, background workers and static sites, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
          end
          deploy = deploy_named(environment_row, resource, arguments["deploy"])
          if History.status(deploy["status"], DEPLOY_STATUSES).then { |status| History::FINISHED.include?(status) }
            fail! "Deploy #{deploy['id']} of #{resource[:name]} already ended as #{deploy['status'].to_s.tr('_', ' ')}, so there is nothing to cancel."
          end

          cancelled = api(environment_row).cancel_deploy(resource[:id], deploy["id"]).to_h
          Telemetry.result("Render is cancelling deploy #{deploy['id']} of #{resource[:name]}, now #{(cancelled['status'] || 'canceled').to_s.tr('_', ' ')}. " \
                           "The deploy that was live before it keeps serving.", link: deploy_link(resource, deploy["id"]))
        end

        def trigger_deploy(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless DEPLOYING.include?(resource[:type])
            fail! "Render deploys web services, private services, background workers, static sites and cron jobs, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
          end

          started = api(environment_row).trigger_deploy(resource[:id], deploy_body(resource, arguments)).to_h
          what = started["id"] ? "Render started deploy #{started['id']} of #{resource[:name]}, now #{started['status'].to_s.tr('_', ' ').presence || 'queued'}." : "Render queued a deploy of #{resource[:name]}."
          Telemetry.result("#{what} Autodeploy is as it was. Follow it with deploy_history.", link: started["id"] ? deploy_link(resource, started["id"]) : link(resource))
        end

        def suspend_service(environment_row:, arguments:)
          resource = suspendable(environment_row, arguments)
          fail! "#{resource[:name]} is already suspended." if suspended?(resource)

          api(environment_row).suspend(SUSPENDABLE.fetch(resource[:type], :service), resource[:id])
          Telemetry.result("Render is suspending #{resource[:name]}. It stops running and serving until resume_service brings it back.", link: link(resource))
        end

        def resume_service(environment_row:, arguments:)
          resource = suspendable(environment_row, arguments)
          fail! "#{resource[:name]} is not suspended, so there is nothing to resume." unless suspended?(resource)

          api(environment_row).resume(SUSPENDABLE.fetch(resource[:type], :service), resource[:id])
          Telemetry.result("Render is resuming #{resource[:name]}. Its events show when it is up again.", link: link(resource))
        end

        # The trigger it had is the answer's before fact, so the undo the registry declares sets it back.
        def set_autodeploy(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless DEPLOYING.include?(resource[:type])
            fail! "Render deploys web services, private services, background workers, static sites and cron jobs on their own, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
          end
          trigger = arguments["trigger"].to_s.strip
          fail! "trigger must be #{AUTODEPLOY_TRIGGERS.to_sentence(last_word_connector: ' or ')}." unless AUTODEPLOY_TRIGGERS.include?(trigger)

          before = api(environment_row).service(resource[:id])["autoDeployTrigger"].presence
          fail! "Autodeploy of #{resource[:name]} is already #{AUTODEPLOY_WORDS.fetch(trigger)}." if before == trigger

          api(environment_row).update_autodeploy(resource[:id], trigger)
          was = " It was #{AUTODEPLOY_WORDS.fetch(before, before)}." if before
          Telemetry.result("Autodeploy of #{resource[:name]} is now #{AUTODEPLOY_WORDS.fetch(trigger)}.#{was}", link: link(resource), facts: { BEFORE => before })
        end

        # Every field Render requires, the ones not given kept from the service's autoscaling now. A target of 0 stops
        # scaling on that resource, and turning autoscaling on needs at least one.
        def set_autoscaling(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless SCALABLE.include?(resource[:type])
            fail! "Render autoscales web services, private services and background workers, and #{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}."
          end

          now = api(environment_row).service(resource[:id]).dig("serviceDetails", "autoscaling") || {}
          config = autoscaling_config(now, arguments)
          api(environment_row).update_autoscaling(resource[:id], config)
          Telemetry.result("Autoscaling of #{resource[:name]} is now #{autoscaling_words(config)}. It was #{now.empty? ? 'never set up' : autoscaling_words(now)}.",
                           link: link(resource))
        end

        # Who started the deploy a cancel would stop, from the build or deploy start Render recorded with the person who
        # triggered it (spec, Build Started and Deploy Started, trigger.user). A deploy Render or a commit started has
        # nobody to ask.
        def owner_of(tool_name, environment_row:, arguments:)
          return super unless tool_name == CANCEL_DEPLOY

          resource = find_resource(environment_row, arguments["resource"])
          deploy = deploy_named(environment_row, resource, arguments["deploy"])
          from = Telemetry.parse_time(deploy["createdAt"]) || Time.current
          events = api(environment_row).events(resource[:id], "type" => PHASE_EVENTS.values_at("build", "deploy").map(&:first), "startTime" => (from - PHASE_MARGIN).utc.iso8601,
                                                              "endTime" => Time.current.utc.iso8601, "limit" => PHASE_EVENT_LIMIT)
          started = events.find { |event| event["type"] == PHASE_EVENTS["deploy"].first && event.dig("details", "deployId") == deploy["id"] } ||
                    events.select { |event| event["type"] == PHASE_EVENTS["build"].first }.min_by { |event| event["timestamp"].to_s }
          email = started&.dig("details", "trigger", "user", "email")
          return if email.blank?

          Owner.new(name: email, email: email, role: Owner::ROLE_STARTED, what: "deploy #{deploy['id']} of #{resource[:name]}")
        end

        private

        def deploy_named(environment_row, resource, asked)
          id = asked.to_s.strip
          fail! "Say which deploy, by the id list_deployments shows." if id.empty?

          api(environment_row).deploy(resource[:id], id)
        rescue RenderApi::NotFound
          fail! "#{resource[:name]} has no deploy #{id}. list_deployments shows its deploys."
        end

        # The body Render takes, refused in words where the spec says two fields cannot go together.
        def deploy_body(resource, arguments)
          commit = arguments["commit"].to_s.strip.presence
          image = arguments["image"].to_s.strip.presence
          deploy_only = ActiveModel::Type::Boolean.new.cast(arguments["deploy_only"])
          clear = ActiveModel::Type::Boolean.new.cast(arguments["clear_cache"])
          fail! "Name a commit or an image, not both." if commit && image
          fail! "deploy_only deploys the last build again, so it takes no commit, image or clear_cache." if deploy_only && (commit || image || clear)
          fail! "Render deploys a cron job's latest commit only, so leave commit out." if commit && resource[:type] == CRON_JOB

          { "commitId" => commit, "imageUrl" => image, "clearCache" => (CLEAR_CACHE if clear), "deployMode" => (DEPLOY_ONLY if deploy_only) }.compact
        end

        def autoscaling_config(now, arguments)
          enabled = arguments["enabled"].nil? ? now["enabled"] == true : ActiveModel::Type::Boolean.new.cast(arguments["enabled"])
          min = whole(arguments, "min") || now["min"]
          max = whole(arguments, "max") || now["max"]
          criteria = %w[cpu memory].to_h do |name|
            asked = whole(arguments, "#{name}_percent")
            kept = now.dig("criteria", name) || {}
            criterion = if asked.nil? then { "enabled" => kept["enabled"] == true, "percentage" => kept["percentage"] }
            elsif asked.zero? then { "enabled" => false, "percentage" => kept["percentage"] }
            else
              fail!("#{name}_percent must be from 1 to 100, or 0 to stop scaling on #{name}.") unless PERCENT.cover?(asked)
              { "enabled" => true, "percentage" => asked }
            end
            [ name, criterion ]
          end
          fail! "Say the fewest and the most instances, since autoscaling has none yet." if min.nil? || max.nil?
          fail! "min must be 1 or more, and max at least min." unless min.to_i >= 1 && max.to_i >= min.to_i
          if enabled && criteria.values.none? { |criterion| criterion["enabled"] }
            fail! "Autoscaling needs a CPU or memory target to scale on. Pass cpu_percent or memory_percent."
          end

          { "enabled" => enabled, "min" => min, "max" => max,
            "criteria" => criteria.transform_values { |criterion| criterion.merge("percentage" => criterion["percentage"] || UNUSED_PERCENT) } }
        end

        def whole(arguments, name)
          return nil if arguments[name].nil?

          Integer(arguments[name], exception: false) || fail!("#{name} must be a whole number.")
        end

        def autoscaling_words(config)
          return "off" unless config["enabled"]

          targets = %w[cpu memory].filter_map { |name| "#{name} #{config.dig('criteria', name, 'percentage')}%" if config.dig("criteria", name, "enabled") }
          "on, between #{config['min']} and #{config['max']} instances, aiming for #{targets.join(' and ')}"
        end

        def suspendable(environment_row, arguments)
          resource = find_resource(environment_row, arguments["resource"])
          fail! "#{resource[:name]} is a workflow, which Render does not suspend." if resource[:type] == WORKFLOW

          resource
        end

        def suspended?(resource) = resource[:status].to_s.start_with?(SUSPENDED)

        def deploy_link(resource, id)
          url = deploy_url(resource, id)
          url ? Telemetry::Link.new(provider: PROVIDER, url: url) : link(resource)
        end
      end
    end
  end
end
