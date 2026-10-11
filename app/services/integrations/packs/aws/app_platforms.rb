module Integrations
  module Packs
    class Aws < NativePack
      # App Runner services and Elastic Beanstalk environments, which run a team's code as services beside ECS. Each is
      # on the map as a service, told apart from an ECS service by its ARN, how it stands is read, and its deploys are run
      # history: an App Runner service's operations (ListOperations) and an environment's events grouped by the request
      # that made them (DescribeEvents RequestId), each from the API references of App Runner and Elastic Beanstalk. App
      # Runner is not offered in every region, so a region AWS's endpoint list does not give it is not read for it.
      module AppPlatforms
        History = Capabilities::History

        APP_RUNNER = "apprunner".freeze
        BEANSTALK = "elasticbeanstalk".freeze
        PLATFORM_NAMES = { APP_RUNNER => "App Runner service", BEANSTALK => "Elastic Beanstalk environment" }.freeze
        PLATFORM_PLURALS = { APP_RUNNER => "App Runner services", BEANSTALK => "Elastic Beanstalk environments" }.freeze
        # The names AWS's endpoint list keeps each service under (Aws::Partitions).
        ENDPOINT_NAMES = { APP_RUNNER => "AppRunner", BEANSTALK => "ElasticBeanstalk" }.freeze

        APP_OPERATIONS = "app_runner_operations".freeze
        ENVIRONMENT_EVENTS = "beanstalk_events".freeze
        DESCRIBE_APP = "describe_app".freeze
        LOGS_QUERY = "logs_insights_query".freeze

        RUN_LIMIT = 20
        # ListOperations answers at most 20 a page. A run by its id is looked for in this many pages.
        OPERATION_PAGES = 5
        EVENTS_READ = 1000
        EVENTS_SHOWN = 10
        LOG_QUERY = "fields @timestamp, @message | sort @timestamp desc | limit 200".freeze
        # An operation's status (OperationStatus). An operation App Runner rolled back did not go out.
        OPERATION_STATUSES = {
          "pending" => History::QUEUED, "in_progress" => History::RUNNING, "rollback_in_progress" => History::RUNNING,
          "succeeded" => History::SUCCEEDED, "failed" => History::FAILED, "rollback_failed" => History::FAILED,
          "rollback_succeeded" => History::FAILED
        }.freeze
        # How an App Runner service stands (ServiceStatus), in the words the map reads.
        SERVICE_STATUSES = {
          "RUNNING" => "running", "OPERATION_IN_PROGRESS" => "in_progress", "PAUSED" => "paused",
          "CREATE_FAILED" => "failed", "DELETE_FAILED" => "failed", "DELETED" => "stopped"
        }.freeze
        # An environment's status while an operation runs (EnvironmentStatus), and its health colour once Ready
        # (EnvironmentHealth). Grey is unknown.
        BUSY_ENVIRONMENT = %w[Launching Updating LinkingFrom LinkingTo Terminating Aborting].freeze
        HEALTH_WORDS = { "Green" => "ready", "Yellow" => "degraded", "Red" => "unhealthy" }.freeze
        # The words Elastic Beanstalk's events end an operation with (Elastic Beanstalk developer guide, Using Elastic
        # Beanstalk with Amazon EventBridge, Elastic Beanstalk event field mapping), and the severities of a failure.
        DONE_MESSAGE = /completed successfully\.\z/
        STARTING_MESSAGE = / is starting\.\z/
        FAILED_SEVERITIES = %w[ERROR FATAL].freeze
        # Whether an environment streams its instances' logs to CloudWatch Logs, and where (Elastic Beanstalk developer
        # guide, Using Elastic Beanstalk with Amazon CloudWatch Logs, log groups named /aws/elasticbeanstalk/<environment>/<file>).
        LOGS_NAMESPACE = "aws:elasticbeanstalk:cloudwatch:logs".freeze
        STREAM_LOGS = "StreamLogs".freeze
        DEPLOY_LOG = "/var/log/eb-engine.log".freeze

        def self.included(pack)
          resource = { "type" => "string", "description" => "An App Runner service or Elastic Beanstalk environment, by its name or ARN" }
          history = {
            "type" => "object",
            "properties" => {
              "resource" => resource,
              "run" => { "type" => "string", "description" => "Only this one, by its id, with its steps (optional)" },
              "name" => { "type" => "string", "description" => "Only runs whose name contains this (optional)" },
              "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT})" }
            },
            "required" => [ "resource" ]
          }

          pack.tool APP_OPERATIONS,
                    description: "An App Runner service's recent operations, newest first: its deployments, updates, pauses and resumes, " \
                                 "each with how it ended, when it started and finished, and how long finished ones usually take. Name an " \
                                 "operation to read it with where its deployment log is",
                    params_schema: history.deep_merge("properties" => { "resource" => { "description" => "The App Runner service, by its name or ARN" } }),
                    read_only: true

          pack.tool ENVIRONMENT_EVENTS,
                    description: "An Elastic Beanstalk environment's recent deployments and updates, newest first, read from its events, each " \
                                 "with how it ended, the version it deployed and the error a failed one gave. Name one by its request id " \
                                 "to read every event it wrote",
                    params_schema: history.deep_merge("properties" => { "resource" => { "description" => "The Elastic Beanstalk environment, by its name or ARN" } }),
                    read_only: true

          pack.tool DESCRIBE_APP,
                    description: "How an App Runner service or Elastic Beanstalk environment is set up and how it stands now: its status, " \
                                 "health, address, what it runs and its latest events. Environment variables are named, never shown",
                    params_schema: { "type" => "object", "properties" => { "resource" => resource }, "required" => [ "resource" ] },
                    read_only: true
        end

        # Which platform an ARN is of, App Runner or Elastic Beanstalk, or nil for anything else.
        def self.platform_of(arn)
          service = arn.to_s.split(":")[2]
          service if PLATFORM_NAMES.key?(service)
        end

        def app_runner_operations(environment_row:, arguments:)
          entry = app_entry!(environment_row, arguments["resource"], APP_RUNNER)
          limit = Capabilities::Answers.limit(arguments, RUN_LIMIT)
          wanted = arguments["run"].to_s.strip.presence
          operations = []
          token = nil
          OPERATION_PAGES.times do
            page = api(environment_row).call(:apprunner, entry.region, :list_operations, { service_arn: entry.arn, max_results: RUN_LIMIT, next_token: token }.compact)
            operations.concat(Array(page[:operation_summary_list]))
            token = page[:next_token]
            break if token.blank? || (wanted.nil? && operations.size >= limit) || operations.any? { |operation| operation[:id] == wanted }
          end
          what = "App Runner service #{entry.name}"
          link = app_link(entry)
          if wanted
            operation = operations.find { |each| each[:id] == wanted } || fail!("#{entry.name} has no operation #{wanted} among its recent ones. app_runner_operations shows them.")
            run = operation_run(operation).with(parts: [ operation_part(entry, operation) ])
            return app_result([ run ], what, link)
          end

          app_result(operations.map { |operation| operation_run(operation) }, what, link, name: arguments["name"], limit: limit)
        end

        def beanstalk_events(environment_row:, arguments:)
          entry = app_entry!(environment_row, arguments["resource"], BEANSTALK)
          aws = api(environment_row)
          environment = environment_of(environment_row, entry)
          events = Array(aws.call(:elasticbeanstalk, entry.region, :describe_events, environment_name: entry.name, max_records: EVENTS_READ)[:events])
          groups = events.select { |event| event[:request_id].present? }.group_by { |event| event[:request_id] }
                         .transform_values { |own| own.sort_by { |event| event[:event_date] || Time.at(0) } }
          newest = groups.max_by { |_, own| own.first[:event_date] || Time.at(0) }&.first
          busy = BUSY_ENVIRONMENT.include?(environment[:status])
          what = "Elastic Beanstalk environment #{entry.name}"
          link = app_link(entry)
          wanted = arguments["run"].to_s.strip.presence
          if wanted
            own = groups[wanted] || fail!("#{entry.name} has no request #{wanted} among its recent events. beanstalk_events shows them.")
            run = request_run(wanted, own, busy && wanted == newest)
            log = deploy_log(environment_row, entry, run)
            parts = own.map { |event| event_part(event, log) }
            return app_result([ run.with(parts: parts) ], what, link)
          end

          runs = groups.map { |id, own| request_run(id, own, busy && id == newest) }
          app_result(runs, what, link, name: arguments["name"], limit: Capabilities::Answers.limit(arguments, RUN_LIMIT))
        end

        def describe_app(environment_row:, arguments:)
          entry = app_entry!(environment_row, arguments["resource"], nil)
          lines = AppPlatforms.platform_of(entry.arn) == APP_RUNNER ? app_runner_lines(environment_row, entry) : environment_lines(environment_row, entry)
          Telemetry.result(lines.compact.join("\n"), link: app_link(entry))
        end

        # The App Runner services and Elastic Beanstalk environments of every region the connection reads, where AWS
        # offers them.
        def app_platform_reading(environment_row, regions)
          entries = []
          gaps = []
          regions.each do |region|
            PLATFORM_NAMES.each_key do |platform|
              next unless offered?(platform, region)

              found, more = platform == APP_RUNNER ? app_runner_services(environment_row, region) : beanstalk_environments(environment_row, region)
              entries.concat(found)
              gaps << ResourceMap::Gap.new(text: "Only the first #{AwsApi::MAX_PAGES} pages of #{PLATFORM_PLURALS.fetch(platform)} in #{region} were read.", kinds: [ SERVICE ]) if more
            rescue Integrations::RateLimited => error
              text = Sentence.join("AWS asked to slow down while listing #{PLATFORM_PLURALS.fetch(platform)} in #{region}, so the rest was not read", error)
              return Reading.new(entries: entries, gaps: gaps + [ ResourceMap::Gap.new(text: text, kinds: [ SERVICE ]) ], stopped: true)
            rescue AwsApi::Error => error
              gaps << ResourceMap::Gap.new(text: Sentence.join("#{PLATFORM_PLURALS.fetch(platform)} in #{region} could not be read", error), kinds: [ SERVICE ])
            end
          end
          Reading.new(entries: entries, gaps: gaps)
        end

        # One service or environment by its ARN, as the sweep reads it, or nil when AWS no longer has it.
        def app_refreshed(environment_row, arn, region)
          if AppPlatforms.platform_of(arn) == APP_RUNNER
            service = api(environment_row).call(:apprunner, region, :describe_service, service_arn: arn)[:service]
            service && service[:status] != "DELETED" ? app_runner_entry(service, region) : nil
          else
            application, name = arn.split(":environment/", 2).last.to_s.split("/", 2)
            environment = Array(api(environment_row).call(:elasticbeanstalk, region, :describe_environments, application_name: application,
                                                                                                             environment_names: [ name ], include_deleted: false)[:environments]).first
            environment && environment_entry(environment, region)
          end
        end

        private

        def offered?(platform, region)
          ::Aws::Partitions.partition(Aws.partition(region)).service(ENDPOINT_NAMES.fetch(platform)).regions.include?(region)
        rescue ArgumentError
          false
        end

        def app_result(runs, what, link, name: nil, limit: RUN_LIMIT)
          History.result(runs, what: what, link: link, name: name, limit: limit)
        end

        def app_runner_services(environment_row, region)
          services, more = api(environment_row).all(:apprunner, region, :list_services, {}, :service_summary_list)
          [ services.reject { |service| service[:status] == "DELETED" }.map { |service| app_runner_entry(service, region) }, more ]
        end

        def app_runner_entry(service, region)
          Entry.new(kind: SERVICE, arn: service[:service_arn], name: service[:service_name], region: region,
                    status: SERVICE_STATUSES[service[:status]], details: { "region" => region, "type" => "App Runner", "url" => service[:service_url] }.compact)
        end

        def beanstalk_environments(environment_row, region)
          environments, more = api(environment_row).all(:elasticbeanstalk, region, :describe_environments, { include_deleted: false }, :environments)
          [ environments.map { |environment| environment_entry(environment, region) }, more ]
        end

        # Busy while an operation runs, and otherwise as its health colour says.
        def environment_entry(environment, region)
          status = BUSY_ENVIRONMENT.include?(environment[:status]) ? "in_progress" : HEALTH_WORDS[environment[:health]]
          Entry.new(kind: SERVICE, arn: environment[:environment_arn], name: environment[:environment_name], region: region, status: status,
                    details: { "region" => region, "type" => "Elastic Beanstalk", "application" => environment[:application_name],
                               "version" => environment[:version_label], "platform" => environment[:solution_stack_name] }.compact)
        end

        # A service or environment by its ARN, or by its name among those of the platform asked (or either, for nil).
        def app_entry!(environment_row, asked, platform)
          wanted = asked.to_s.strip
          what = platform ? PLATFORM_NAMES.fetch(platform) : "App Runner service or Elastic Beanstalk environment"
          fail!("Say which #{what}, by its name or ARN.") if wanted.empty?

          parts = wanted.match(ARN)
          if parts
            fail!("#{wanted} is in #{parts[:region]}, which this connection does not read.") if regions(environment_row).exclude?(parts[:region])
            found = AppPlatforms.platform_of(wanted)
            fail!("#{wanted} is not #{what.start_with?('A') ? 'an' : 'a'} #{what}.") unless found && (platform.nil? || found == platform)

            return app_refreshed(environment_row, wanted, parts[:region]) || fail!("AWS has no #{PLATFORM_NAMES.fetch(found)} #{wanted}.")
          end

          platforms = platform ? [ platform ] : PLATFORM_NAMES.keys
          listed = regions(environment_row).flat_map do |region|
            platforms.select { |each| offered?(each, region) }.flat_map do |each|
              each == APP_RUNNER ? app_runner_services(environment_row, region).first : beanstalk_environments(environment_row, region).first
            end
          end
          Named.find(listed, wanted, id: :arn, name: :name, provider: PROVIDER, describe: ->(entry) { "#{entry.details['type']} #{entry.arn}" }, connection: environment_row) ||
            fail!("No #{what} called #{wanted} in #{regions(environment_row).join(', ')}.")
        end

        def operation_run(operation)
          status = History.status(operation[:status], OPERATION_STATUSES)
          History::Run.new(id: operation[:id], name: operation[:type].to_s.downcase.tr("_", " "), status: status,
                           started_at: Capabilities::RunHistory.time(operation[:started_at]),
                           finished_at: (Capabilities::RunHistory.time(operation[:ended_at] || operation[:updated_at]) if History::FINISHED.include?(status)),
                           detail: (operation[:status].to_s.downcase.tr("_", " ") if operation[:status].to_s.start_with?("ROLLBACK")))
        end

        # An operation writes what it did to the service's service log group (App Runner developer guide, Viewing App Runner
        # logs streamed to CloudWatch Logs: /aws/apprunner/<service name>/<service id>/service), read over its time.
        def operation_part(entry, operation)
          run = operation_run(operation)
          id = entry.arn.split("/").last
          window = { "start" => run.started_at&.utc&.iso8601, "end" => (run.finished_at || Time.current).utc.iso8601 }.compact
          History::Part.new(id: operation[:id], name: run.name, status: run.status, started_at: run.started_at, finished_at: run.finished_at, detail: run.detail,
                            log: { History::LOG_TOOL => LOGS_QUERY,
                                   History::LOG_ARGUMENTS => { "log_groups" => [ "/aws/apprunner/#{entry.name}/#{id}/service" ], "query" => LOG_QUERY, "region" => entry.region }.merge(window) })
        end

        # One request's events as a run. It ended when an event says it completed successfully or one of its events is an
        # error. The newest request of an environment still busy is still going. Any other ended without an error.
        def request_run(id, own, going)
          started = own.find { |event| event[:message].to_s.match?(STARTING_MESSAGE) } || own.first
          failed = own.find { |event| FAILED_SEVERITIES.include?(event[:severity]) }
          done = own.reverse.find { |event| event[:message].to_s.match?(DONE_MESSAGE) }
          status = if failed then History::FAILED
          elsif done then History::SUCCEEDED
          elsif going then History::RUNNING
          else History::SUCCEEDED
          end
          version = own.filter_map { |event| event[:version_label].presence }.last
          History::Run.new(id: id, name: started[:message].to_s.sub(STARTING_MESSAGE, "").presence || "operation", status: status,
                           started_at: Capabilities::RunHistory.time(own.first[:event_date]),
                           finished_at: (Capabilities::RunHistory.time(own.last[:event_date]) if History::FINISHED.include?(status)),
                           detail: [ ("version #{version}" if version), failed&.dig(:message) ].compact.join(", ").presence)
        end

        def event_part(event, log)
          failed = FAILED_SEVERITIES.include?(event[:severity])
          at = Capabilities::RunHistory.time(event[:event_date])
          History::Part.new(id: "#{event[:request_id]} #{at&.to_i}", name: event[:message].to_s.truncate(120), status: failed ? History::FAILED : History::SUCCEEDED,
                            started_at: at, finished_at: at, detail: (event[:severity].to_s.downcase unless event[:severity] == "INFO"), log: (log if failed))
        end

        # The deploy log on the instances, eb-engine.log on Amazon Linux 2 and later, when the environment streams it.
        def deploy_log(environment_row, entry, run)
          application = entry.details["application"] || entry.arn.split(":environment/", 2).last.to_s.split("/").first
          settings = Array(api(environment_row).call(:elasticbeanstalk, entry.region, :describe_configuration_settings,
                                                     application_name: application, environment_name: entry.name)[:configuration_settings]).first || {}
          streaming = Array(settings[:option_settings]).any? { |option| option[:namespace] == LOGS_NAMESPACE && option[:option_name] == STREAM_LOGS && option[:value] == "true" }
          return unless streaming

          window = { "start" => run.started_at&.utc&.iso8601, "end" => (run.finished_at || Time.current).utc.iso8601 }.compact
          { History::LOG_TOOL => LOGS_QUERY,
            History::LOG_ARGUMENTS => { "log_groups" => [ "/aws/elasticbeanstalk/#{entry.name}#{DEPLOY_LOG}" ], "query" => LOG_QUERY, "region" => entry.region }.merge(window) }
        rescue AwsApi::Error
          nil
        end

        def environment_of(environment_row, entry)
          application = entry.details["application"] || entry.arn.split(":environment/", 2).last.to_s.split("/").first
          Array(api(environment_row).call(:elasticbeanstalk, entry.region, :describe_environments, application_name: application,
                                                                                                   environment_names: [ entry.name ], include_deleted: false)[:environments]).first ||
            fail!("Elastic Beanstalk has no environment #{entry.name}.")
        end

        # What a service runs and how. Its environment variables are named only, never shown.
        def app_runner_lines(environment_row, entry)
          service = api(environment_row).call(:apprunner, entry.region, :describe_service, service_arn: entry.arn)[:service] || fail!("App Runner has no service #{entry.arn}.")
          source = service[:source_configuration] || {}
          image = source[:image_repository] || {}
          code = source[:code_repository] || {}
          variables = (image.dig(:image_configuration, :runtime_environment_variables) || code.dig(:code_configuration, :code_configuration_values, :runtime_environment_variables)).to_h.keys
          check = service[:health_check_configuration] || {}
          [
            "#{service[:service_name]}, App Runner service in #{entry.region}, status #{service[:status]}, at https://#{service[:service_url]}",
            ("Runs image #{image[:image_identifier]}" if image[:image_identifier]),
            ("Builds from #{code[:repository_url]}, #{code.dig(:source_code_version, :type).to_s.downcase} #{code.dig(:source_code_version, :value)}" if code[:repository_url]),
            "Deploys on its own when the source changes: #{source[:auto_deployments_enabled] ? 'yes' : 'no'}",
            "#{service.dig(:instance_configuration, :cpu)} CPU, #{service.dig(:instance_configuration, :memory)} memory",
            ("Health check #{check[:protocol]}#{" #{check[:path]}" if check[:path]}, every #{check[:interval]}s" if check[:protocol]),
            ("Environment variables: #{variables.join(' ')}" if variables.any?),
            "Updated #{time(service[:updated_at])}"
          ]
        end

        def environment_lines(environment_row, entry)
          environment = environment_of(environment_row, entry)
          events = Array(api(environment_row).call(:elasticbeanstalk, entry.region, :describe_events, environment_name: entry.name, max_records: EVENTS_SHOWN)[:events])
          [
            "#{environment[:environment_name]}, Elastic Beanstalk environment of #{environment[:application_name]} in #{entry.region}, #{environment[:tier]&.dig(:name)}",
            "Status #{environment[:status]}, health #{environment[:health]}#{" (#{environment[:health_status]})" if environment[:health_status]}",
            "Runs version #{environment[:version_label] || 'none'} on #{environment[:solution_stack_name] || environment[:platform_arn]}",
            ("At #{environment[:endpoint_url] || environment[:cname]}" if environment[:endpoint_url] || environment[:cname]),
            ("An operation can be aborted now." if environment[:abortable_operation_in_progress]),
            ("Latest events, newest first:\n#{events.map { |event| "#{time(event[:event_date])} #{event[:severity]} #{event[:message]}" }.join("\n")}" if events.any?)
          ]
        end

        # The service's list in the console, since AWS documents no address for one service or environment.
        def app_link(entry)
          AppPlatforms.platform_of(entry.arn) == APP_RUNNER ? console_link(entry.region, "apprunner/home") : console_link(entry.region, "elasticbeanstalk/home")
        end
      end
    end
  end
end
