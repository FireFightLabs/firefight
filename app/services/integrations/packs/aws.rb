module Integrations
  module Packs
    # AWS for one account per environment, in the regions the connection names: its ECS services, Lambda functions, EC2
    # instances and RDS databases, their CloudWatch logs and metrics, ECS deployments and Lambda versions, and three
    # changes Halon may make when the keys allow them and an admin switched the tools on (roll an ECS service or a Lambda
    # alias back, restart an ECS service, scale one). Every call goes through AWS's SDK for Ruby (Integrations::AwsApi),
    # with the operations, parameters and answers the API references of ECS, Lambda, EC2, RDS, CloudWatch and
    # CloudWatch Logs give. The metric names, dimensions and statistics are the ones each service's CloudWatch metrics
    # page documents (AWS/ECS, AWS/Lambda, AWS/EC2, AWS/RDS). Console addresses are AWS's regional console host
    # (https://<region>.console.aws.amazon.com, from the console's own guide) with the service paths AWS's guides link to.
    class Aws < NativePack
      # The environment row's credentials, which only this pack reads.
      ACCESS_KEY_ID = "access_key_id".freeze
      SECRET_ACCESS_KEY = "secret_access_key".freeze
      REGIONS = "regions".freeze

      PROVIDER = "AWS".freeze
      PROVIDER_KEY = "aws".freeze
      # Console addresses are documented for the aws partition only, so China and GovCloud resources get no link.
      CONSOLE_PARTITION = "aws".freeze

      SERVICE = ResourceMap::KIND_SERVICE
      FUNCTION = ResourceMap::KIND_FUNCTION
      INSTANCE = ResourceMap::KIND_VIRTUAL_MACHINE
      DATABASE = ResourceMap::KIND_DATABASE
      KIND_NAMES = { SERVICE => "ECS service", FUNCTION => "Lambda function", INSTANCE => "EC2 instance", DATABASE => "RDS database" }.freeze
      KIND_ARTICLED = { SERVICE => "an ECS service", FUNCTION => "a Lambda function", INSTANCE => "an EC2 instance", DATABASE => "an RDS database" }.freeze
      KIND_PLURALS = { SERVICE => "ECS services", FUNCTION => "Lambda functions", INSTANCE => "EC2 instances", DATABASE => "RDS databases" }.freeze

      # One CloudWatch metric as Firefight reads it: the statistic AWS's metrics page recommends, the unit shown, what a
      # reading is multiplied by to reach it, and whether it is a sum per period, which is shown per minute so a reading
      # compares with a baseline whatever the period.
      Metric = Data.define(:title, :stat, :unit, :scale, :summed)
      PERCENT = "%".freeze
      COUNT = "count".freeze
      PER_MINUTE = "per minute".freeze
      MEGABYTE = 1.0 / (1024 * 1024)
      NAMESPACES = { SERVICE => "AWS/ECS", FUNCTION => "AWS/Lambda", INSTANCE => "AWS/EC2", DATABASE => "AWS/RDS" }.freeze
      METRICS = {
        SERVICE => {
          "CPUUtilization" => Metric.new(title: "CPU", stat: "Average", unit: PERCENT, scale: 1, summed: false),
          "MemoryUtilization" => Metric.new(title: "Memory", stat: "Average", unit: PERCENT, scale: 1, summed: false)
        },
        FUNCTION => {
          "Invocations" => Metric.new(title: "Invocations", stat: "Sum", unit: COUNT, scale: 1, summed: true),
          "Errors" => Metric.new(title: "Errors", stat: "Sum", unit: COUNT, scale: 1, summed: true),
          "Throttles" => Metric.new(title: "Throttles", stat: "Sum", unit: COUNT, scale: 1, summed: true),
          "Duration" => Metric.new(title: "Duration, average", stat: "Average", unit: "ms", scale: 1, summed: false),
          "ConcurrentExecutions" => Metric.new(title: "Concurrent executions", stat: "Maximum", unit: COUNT, scale: 1, summed: false)
        },
        INSTANCE => {
          "CPUUtilization" => Metric.new(title: "CPU", stat: "Average", unit: PERCENT, scale: 1, summed: false),
          "NetworkIn" => Metric.new(title: "Network in", stat: "Sum", unit: "MB", scale: MEGABYTE, summed: true),
          "NetworkOut" => Metric.new(title: "Network out", stat: "Sum", unit: "MB", scale: MEGABYTE, summed: true),
          "StatusCheckFailed" => Metric.new(title: "Status check failed", stat: "Maximum", unit: COUNT, scale: 1, summed: false)
        },
        DATABASE => {
          "CPUUtilization" => Metric.new(title: "CPU", stat: "Average", unit: PERCENT, scale: 1, summed: false),
          "DatabaseConnections" => Metric.new(title: "Connections", stat: "Average", unit: COUNT, scale: 1, summed: false),
          "FreeableMemory" => Metric.new(title: "Freeable memory", stat: "Average", unit: "MB", scale: MEGABYTE, summed: false),
          "FreeStorageSpace" => Metric.new(title: "Free storage", stat: "Average", unit: "MB", scale: MEGABYTE, summed: false),
          "ReadLatency" => Metric.new(title: "Read latency", stat: "Average", unit: "ms", scale: 1000, summed: false),
          "WriteLatency" => Metric.new(title: "Write latency", stat: "Average", unit: "ms", scale: 1000, summed: false)
        }
      }.freeze
      METRIC_NAMES = METRICS.values.flat_map(&:keys).uniq.freeze
      DEFAULT_METRICS = {
        SERVICE => %w[CPUUtilization MemoryUtilization], FUNCTION => %w[Invocations Errors Duration Throttles],
        INSTANCE => %w[CPUUtilization StatusCheckFailed NetworkIn NetworkOut],
        DATABASE => %w[CPUUtilization DatabaseConnections FreeableMemory FreeStorageSpace]
      }.freeze
      BASELINE_METRICS = {
        SERVICE => %w[CPUUtilization MemoryUtilization], FUNCTION => %w[Invocations Errors Duration Throttles],
        INSTANCE => %w[CPUUtilization NetworkIn NetworkOut], DATABASE => %w[CPUUtilization DatabaseConnections FreeableMemory ReadLatency WriteLatency]
      }.freeze
      # A week read for a baseline comes back an hour a point, well inside GetMetricData's limit on points.
      BASELINE_PERIOD = 3600

      DEFAULT_MINUTES = 60
      MAX_MINUTES = 7 * 24 * 60
      LOG_LIMIT = 200
      QUERY_ROWS = 500
      QUERY_LIMIT = 10_000
      # Logs Insights runs a query in the background, so a call waits for it this long and gives up rather than hang.
      QUERY_WAIT = 25
      QUERY_POLL = 1
      QUERY_DONE = %w[Complete Failed Cancelled Timeout Unknown].freeze
      DEPLOYMENT_LIMIT = 20
      VERSION_LIMIT = 20
      VERSION_PAGES = 100
      # ListTasks answers at most 100 a page and DescribeTasks takes at most 100 tasks a call.
      TASK_LIMIT = 50
      REVISIONS_SHOWN = 10
      EVENTS_SHOWN = 10
      LISTED_PER_KIND = 100
      # DescribeServices takes at most 10 services a call, DescribeServiceDeployments and DescribeServiceRevisions 20.
      SERVICES_PER_CALL = 10
      ARNS_PER_CALL = 20
      # The states DescribeInstances reports for an instance that still exists.
      LIVE_INSTANCE_STATES = %w[pending running shutting-down stopping stopped].freeze
      AWSLOGS = "awslogs".freeze
      # Names AWS gives a task definition family, a Lambda alias and the log names Firefight writes into a query, from
      # each API reference. Anything else is refused rather than escaped, since Logs Insights documents no escaping.
      TASK_DEFINITION = /\A(?<family>[A-Za-z0-9_-]{1,255}):(?<revision>\d+)\z/
      TASK_DEFINITION_ARN = %r{\Aarn:[a-z-]+:ecs:[a-z0-9-]+:\d{12}:task-definition/(?<family>[A-Za-z0-9_-]{1,255}):(?<revision>\d+)\z}
      LAMBDA_TARGET = /\A(?:(?<alias>[A-Za-z0-9_-]*[A-Za-z_-][A-Za-z0-9_-]*):)?(?<version>\d+)\z/
      SAFE_NAME = %r{\A[\w./#-]+\z}
      UNQUOTABLE = /["\\]/
      UNESCAPED_SLASH = %r{(?<!\\)/}
      ARN = /\Aarn:(?<partition>[a-z-]+):(?<service>[a-z0-9-]+):(?<region>[a-z0-9-]*):(?<account>\d*):(?<resource>.+)\z/

      RANGE = {
        "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze
      RESOURCE = { "type" => "string", "description" => "An ECS service, Lambda function, EC2 instance or RDS database, by its name or ARN as list_resources shows it" }.freeze

      tool :list_resources,
           description: "The ECS services, Lambda functions, EC2 instances and RDS databases this connection reaches, in each of " \
                        "its regions, with their state and ARN. Use it first to find the name to pass to the other tools",
           params_schema: {
             "type" => "object",
             "properties" => {
               "kind" => { "type" => "string", "enum" => KIND_NAMES.keys, "description" => "Only this kind (optional)" },
               "region" => { "type" => "string", "description" => "Only this region, such as eu-west-1 (optional, every region of the connection)" }
             }
           },
           read_only: true

      tool :describe_resource,
           description: "How one resource is set up and how it stands now. An ECS service: its rollout, task counts, task " \
                        "definition, containers, health checks, load balancers and latest events. A Lambda function: its state, " \
                        "last update, runtime, memory, timeout and aliases. An EC2 instance: its state, type and status checks. An " \
                        "RDS database: its status, engine, class, storage, pending changes and latest events. Environment " \
                        "variables are named, never shown",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: true

      tool :search_logs,
           description: "Log lines of one ECS service, Lambda function or RDS database from CloudWatch Logs, newest first, at most " \
                        "#{LOG_LIMIT}, through a Logs Insights query on its log groups. Filter by text, a regular expression or text to " \
                        "leave out. An ECS service is read from the awslogs log group its task definition names, a Lambda function " \
                        "from its own log group, an RDS database from the logs it exports",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "text" => { "type" => "string", "description" => "Only lines containing this text, case sensitive (optional)" },
               "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :logs_insights_query,
           description: "Run a CloudWatch Logs Insights query, in the Logs Insights query language, on log groups in one region, " \
                        "such as fields @timestamp, @message | filter @message like /timeout/ | stats count(*) by bin(5m). Use it " \
                        "for counts, groupings and log groups search_logs does not read. Logs Insights charges by the data it scans, " \
                        "so keep the range short",
           params_schema: {
             "type" => "object",
             "properties" => {
               "log_groups" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The log groups to query, by name" },
               "query" => { "type" => "string", "description" => "The Logs Insights query" },
               "region" => { "type" => "string", "description" => "The region the log groups are in (optional, the connection's first region)" },
               "limit" => { "type" => "integer", "description" => "At most this many rows (optional, #{QUERY_ROWS})" },
               **RANGE
             },
             "required" => %w[log_groups query]
           },
           read_only: true

      tool :cloudwatch_metrics,
           description: "CloudWatch metrics of one resource over time, with min, average, max and latest, and the person sees each " \
                        "as a chart. An ECS service has CPUUtilization and MemoryUtilization. A Lambda function has Invocations, " \
                        "Errors, Throttles, Duration and ConcurrentExecutions. An EC2 instance has CPUUtilization, NetworkIn, " \
                        "NetworkOut and StatusCheckFailed. An RDS database has CPUUtilization, DatabaseConnections, FreeableMemory, " \
                        "FreeStorageSpace, ReadLatency and WriteLatency. Counts are shown per minute",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRIC_NAMES },
                              "description" => "Which metrics, by their CloudWatch name (optional, the resource's usual ones)" },
               **RANGE
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_deployments,
           description: "What went out to an ECS service or a Lambda function, newest first. An ECS service: its deployments, when, " \
                        "how each ended and the task definition it rolled out, with the revisions a rollback can go back " \
                        "to. A Lambda function: its published versions and the alias pointing at each. Use it to see what changed " \
                        "before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{DEPLOYMENT_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :list_tasks,
           description: "The tasks of an ECS service, newest first: the ones running and the ones stopped in the last hour or so, " \
                        "with why each stopped (its stop code and reason) and each container's exit code. Many stopped tasks mean " \
                        "the service keeps replacing them",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "limit" => { "type" => "integer", "description" => "At most this many of each, running and stopped (optional, #{TASK_LIMIT})" }
             },
             "required" => [ "resource" ]
           },
           read_only: true

      tool :rollback_deployment,
           description: "Put an ECS service back on an earlier revision of its task definition, or move a Lambda function's alias " \
                        "back to an earlier version. list_deployments gives the revisions and versions",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "to" => { "type" => "string", "description" => "For an ECS service, the task definition as family:revision, such as web:41. For " \
                                                              "a Lambda function, the version, or alias:version, such as live:12, when it has more than one alias" }
             },
             "required" => %w[resource to]
           },
           read_only: false

      tool :restart_service,
           description: "Start a new deployment of an ECS service on the task definition it already runs, which replaces every task. " \
                        "For a service stuck in a bad state while its code is fine",
           params_schema: { "type" => "object", "properties" => { "resource" => RESOURCE }, "required" => [ "resource" ] },
           read_only: false

      tool :scale_service,
           description: "Set how many tasks an ECS service runs. An auto scaling policy on the service can change it again",
           params_schema: {
             "type" => "object",
             "properties" => {
               "resource" => RESOURCE,
               "desired_count" => { "type" => "integer", "description" => "How many tasks to run, 0 or more" }
             },
             "required" => %w[resource desired_count]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: ACCESS_KEY_ID, label: "Access key ID", secret: false, placeholder: "AKIA...",
                              hint: "The access key of an IAM user that can read ECS, Lambda, EC2, RDS, CloudWatch metrics and CloudWatch Logs Insights. For Halon to apply fixes, it can also update ECS services and Lambda aliases."),
          CredentialField.new(key: SECRET_ACCESS_KEY, label: "Secret access key", secret: true, placeholder: "",
                              hint: "The secret shown once when the access key was created."),
          CredentialField.new(key: REGIONS, label: "Regions", secret: false, placeholder: "us-east-1, eu-west-1",
                              hint: "The regions this environment runs in, separated by commas. Halon reads only these.")
        ]
      end

      # Asks AWS who the keys belong to, so wrong keys or a mistyped region are said on the form before anything is saved.
      def self.credential_refusal(values, region: nil)
        key = values[ACCESS_KEY_ID].to_s.strip
        secret = values[SECRET_ACCESS_KEY].to_s.strip
        regions = regions_from(values[REGIONS])
        return "Paste an access key ID." if key.empty?
        return "Paste the secret access key." if secret.empty?
        return "Enter at least one region, such as us-east-1." if regions.empty?

        unknown = regions.reject { |region| AwsApi.region?(region) }
        return "AWS has no region called #{unknown.to_sentence}. Use region codes, such as eu-west-1." if unknown.any?

        AwsApi.new(access_key_id: key, secret_access_key: secret).identity(regions.first)
        nil
      rescue AwsApi::Error => error
        "AWS refused these keys. #{error.message}"
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(ACCESS_KEY_ID, values[ACCESS_KEY_ID].to_s.strip)
        environment_row.store_credential!(SECRET_ACCESS_KEY, values[SECRET_ACCESS_KEY].to_s.strip)
        environment_row.store_credential!(REGIONS, regions_from(values[REGIONS]).join(","))
      end

      def self.regions_from(value) = value.to_s.downcase.split(/[\s,]+/).reject(&:empty?).uniq

      def list_resources(environment_row:, arguments:)
        kind = arguments["kind"].presence
        fail!("kind must be one of #{KIND_NAMES.keys.join(', ')}.") if kind && !KIND_NAMES.key?(kind)
        region = arguments["region"].presence
        fail!("This connection does not read #{region}. It reads #{regions(environment_row).join(', ')}.") if region && regions(environment_row).exclude?(region)

        reading = inventory(environment_row, kinds: kind ? [ kind ] : KIND_NAMES.keys, regions: region ? [ region ] : regions(environment_row))
        sections = (kind ? [ kind ] : KIND_NAMES.keys).filter_map do |each|
          rows = reading.entries.select { |entry| entry.kind == each }
          next if rows.empty?

          lines = rows.first(LISTED_PER_KIND).map { |entry| "#{entry.name} (#{entry.arn}), #{entry.region}, #{entry.status || 'unknown'}" }
          lines << "#{rows.size - LISTED_PER_KIND} more not shown. Ask for one region or kind to see them." if rows.size > LISTED_PER_KIND
          "#{KIND_PLURALS.fetch(each)}:\n#{lines.join("\n")}"
        end
        asked = region ? [ region ] : regions(environment_row)
        text = sections.any? ? sections.join("\n\n") : "Nothing found in #{asked.join(', ')}."
        text = "#{text}\n\nNot read:\n#{reading.gaps.join("\n")}" if reading.gaps.any?
        Telemetry.result(text, link: console_link(asked.first, "console/home"))
      end

      def describe_resource(environment_row:, arguments:)
        entry = find_resource(environment_row, arguments["resource"])
        lines = case entry.kind
        when SERVICE then service_lines(environment_row, entry)
        when FUNCTION then function_lines(environment_row, entry)
        when INSTANCE then instance_lines(environment_row, entry)
        else database_lines(environment_row, entry)
        end
        Telemetry.result(lines.compact.join("\n"), link: resource_link(entry))
      end

      def search_logs(environment_row:, arguments:)
        entry = find_resource(environment_row, arguments["resource"])
        region, groups, streams = log_source(environment_row, entry)
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        limit = limit(arguments, LOG_LIMIT)
        query = log_query(arguments, streams, limit)
        rows = run_query(environment_row, region, groups, query, started, ended, limit)
        lines = rows.filter_map do |row|
          at = insights_time(row["@timestamp"])
          Telemetry::LogLine.new(at: at, source: row["@logStream"].to_s, text: row["@message"].to_s) if at
        end
        asked = "#{entry.name} in #{groups.join(', ')} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: console_link(region, "cloudwatch/home", "logs:"))
      end

      def logs_insights_query(environment_row:, arguments:)
        groups = Array(arguments["log_groups"]).map { |group| group.to_s.strip }.reject(&:empty?).uniq
        fail!("Name at least one log group.") if groups.empty?
        query = arguments["query"].to_s.strip
        fail!("Write the Logs Insights query to run.") if query.empty?
        region = arguments["region"].presence || regions(environment_row).first
        fail!("This connection does not read #{region}. It reads #{regions(environment_row).join(', ')}.") if regions(environment_row).exclude?(region)

        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        shown = limit(arguments, QUERY_ROWS)
        rows = run_query(environment_row, region, groups, query, started, ended, QUERY_LIMIT)
        link = console_link(region, "cloudwatch/home", "logs:")
        return Telemetry.result("The query matched nothing in #{groups.join(', ')} from #{started.utc.iso8601} to #{ended.utc.iso8601}.", link: link) if rows.empty?

        lines = rows.first(shown).map { |row| row.map { |field, value| "#{field}=#{value.to_s.truncate(Telemetry::LOG_CELL_LIMIT)}" }.join(" ") }
        cut = rows.size > shown ? " Only the first #{shown} are shown." : ""
        Telemetry.result("#{rows.size} rows from #{groups.join(', ')}, #{started.utc.iso8601} to #{ended.utc.iso8601}.#{cut}\n#{lines.join("\n")}", link: link)
      end

      def cloudwatch_metrics(environment_row:, arguments:)
        entry = find_resource(environment_row, arguments["resource"])
        known = METRICS.fetch(entry.kind)
        asked = Array(arguments["metrics"]).map(&:to_s).uniq
        missing = asked - known.keys
        fail!("#{KIND_ARTICLED.fetch(entry.kind).upcase_first} has no #{missing.join(', ')} in CloudWatch. It has #{known.keys.join(', ')}.") if missing.any?

        names = asked.presence || DEFAULT_METRICS.fetch(entry.kind)
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        period = period_for(started, ended)
        series = metric_data(environment_row, entry, names, started, ended, period)
        link = metrics_link(entry)
        charts = names.map do |name|
          metric = known.fetch(name)
          Telemetry::Chart.new(title: "#{metric.title} of #{entry.name}", unit: metric.summed ? per_minute(metric.unit) : metric.unit,
                               series: [ Telemetry::Series.new(label: entry.name, points: series.fetch(name, [])) ], from: started, to: ended, link: link&.url)
        end
        Telemetry.result("#{entry.name}, read every #{period / 60} minutes\n#{Telemetry.charts_text(charts)}", charts: charts, link: link)
      end

      def list_deployments(environment_row:, arguments:)
        entry = find_resource(environment_row, arguments["resource"])
        case entry.kind
        when SERVICE then service_deployments(environment_row, entry, limit(arguments, DEPLOYMENT_LIMIT))
        when FUNCTION then function_versions(environment_row, entry, limit(arguments, VERSION_LIMIT))
        else fail!("#{entry.name} is #{KIND_ARTICLED.fetch(entry.kind)}, and only ECS services and Lambda functions have deployments.")
        end
      end

      # ECS keeps a stopped task for about an hour, its own guide says, so older stops are only in the service's events.
      def list_tasks(environment_row:, arguments:)
        entry = ecs_service!(environment_row, arguments["resource"], "have tasks")
        most = limit(arguments, TASK_LIMIT)
        aws = api(environment_row)
        arns = %w[RUNNING STOPPED].flat_map do |state|
          Array(aws.call(:ecs, entry.region, :list_tasks, cluster: entry.cluster, service_name: entry.name, desired_status: state, max_results: most)[:task_arns])
        end.uniq
        link = resource_link(entry)
        return Telemetry.result("#{entry.name} has no running tasks and none stopped recently.", link: link) if arns.empty?

        tasks = Array(aws.call(:ecs, entry.region, :describe_tasks, cluster: entry.cluster, tasks: arns)[:tasks]).sort_by { |task| task[:created_at] || Time.at(0) }.reverse
        running = tasks.count { |task| task[:last_status] == "RUNNING" }
        stopped = tasks.count { |task| task[:last_status] == "STOPPED" }
        Telemetry.result("#{entry.name}: #{running} running, #{stopped} stopped recently, newest first.\n#{tasks.map { |task| task_line(task) }.join("\n")}", link: link)
      end

      def rollback_deployment(environment_row:, arguments:)
        entry = find_resource(environment_row, arguments["resource"])
        to = arguments["to"].to_s.strip
        fail!("Say what to roll back to, as list_deployments shows it.") if to.empty?

        case entry.kind
        when SERVICE then rollback_service(environment_row, entry, to)
        when FUNCTION then rollback_function(environment_row, entry, to)
        else fail!("#{entry.name} is #{KIND_ARTICLED.fetch(entry.kind)}, and only ECS services and Lambda functions can be rolled back here.")
        end
      end

      def restart_service(environment_row:, arguments:)
        entry = ecs_service!(environment_row, arguments["resource"], "can be restarted")
        changing(entry) do
          api(environment_row).call(:ecs, entry.region, :update_service, cluster: entry.cluster, service: entry.arn, force_new_deployment: true)
        end
        Telemetry.result("#{entry.name} is starting a new deployment on the task definition it runs, which replaces every task. " \
                         "Nothing to undo. Follow it with describe_resource.", link: resource_link(entry))
      end

      def scale_service(environment_row:, arguments:)
        count = Integer(arguments["desired_count"], exception: false)
        fail!("desired_count must be a whole number, 0 or more.") unless count && count >= 0
        entry = ecs_service!(environment_row, arguments["resource"], "can be scaled")
        before = describe_service(environment_row, entry)[:desired_count].to_i
        fail!("#{entry.name} already wants #{count} tasks.") if count == before
        changing(entry) do
          api(environment_row).call(:ecs, entry.region, :update_service, cluster: entry.cluster, service: entry.arn, desired_count: count)
        end
        Telemetry.result("#{entry.name} now wants #{count} tasks, #{count > before ? 'up' : 'down'} from #{before}. Undo by scaling it back " \
                         "to #{before}. An auto scaling policy on the service can change the count again.", link: resource_link(entry))
      end

      # The account on the resource map, per region: its ECS services, Lambda functions, EC2 instances and RDS databases,
      # each with its page in the console. A list AWS refuses, or one cut short, is a gap, and its kind is not taken as gone.
      def map_of(environment_row)
        reading = inventory(environment_row, kinds: KIND_NAMES.keys, regions: regions(environment_row))
        account = account_of(environment_row)
        resources = reading.entries.map do |entry|
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: account, kind: entry.kind, external_id: entry.arn, name: entry.name,
                                 status: entry.status, url: resource_link(entry)&.url, details: entry.details)
        end
        ResourceMap::Snapshot.new(resources: resources, gaps: reading.gaps, unread_kinds: reading.unread)
      end

      # What normal looks like, one GetMetricData call per resource for a week an hour a point. Counts become counts per
      # minute, so a live reading compares with them. A resource AWS cannot read keeps yesterday's baselines, and being
      # asked to slow down stops the whole read.
      def baselines_of(environment_row, resources, window)
        resources.flat_map do |resource|
          names = BASELINE_METRICS[resource.kind]
          entry = entry_from_arn(resource.external_id, environment_row) if names
          next [] unless entry

          series = metric_data(environment_row, entry, names, window.begin, window.end, BASELINE_PERIOD)
          names.filter_map do |name|
            metric = METRICS.fetch(entry.kind).fetch(name)
            points = series.fetch(name, [])
            next if points.empty?

            ResourceMap::Baseline::Found.new(key: resource.key, metric: name, label: metric.title, unit: metric.summed ? per_minute(metric.unit) : metric.unit, points: points)
          end
        rescue AwsApi::RateLimited
          raise
        rescue AwsApi::Error, NativePack::Error => error
          Rails.logger.warn("baseline_sweep.resource_failed resource=#{resource.id} error=#{error.message}")
          []
        end
      end

      def check_health!(environment_row)
        account_of(environment_row)
      rescue AwsApi::Error => error
        fail! error.message
      end

      # A resource as the tools address it: its kind, ARN, name, region, and the cluster an ECS service runs in.
      Entry = Data.define(:kind, :arn, :name, :region, :cluster, :status, :details) do
        def initialize(cluster: nil, status: nil, details: {}, **) = super
      end
      Reading = Data.define(:entries, :gaps, :unread)

      private

      # One client per environment row, so the SDK's clients are reused across one call's requests.
      def api(environment_row)
        (@apis ||= {})[environment_row.id] ||= begin
          credentials = environment_row.credentials_hash
          key = credentials[ACCESS_KEY_ID]
          secret = credentials[SECRET_ACCESS_KEY]
          fail!("This environment has no AWS access key. Reconnect it on the Integrations page.") if key.blank? || secret.blank?

          AwsApi.new(access_key_id: key, secret_access_key: secret)
        end
      end

      def regions(environment_row)
        found = self.class.regions_from(environment_row.credentials_hash[REGIONS])
        found.presence || fail!("This environment names no AWS region. Reconnect it on the Integrations page.")
      end

      def account_of(environment_row)
        (@accounts ||= {})[environment_row.id] ||= api(environment_row).identity(regions(environment_row).first)[:account]
      end

      def limit(arguments, most) = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, most ].min : most

      # What the connection reaches, kind by kind and region by region. A list AWS refuses is a gap and leaves the rest
      # read, and being asked to slow down stops the read, with every kind left unread.
      def inventory(environment_row, kinds:, regions:)
        entries = []
        gaps = []
        unread = []
        regions.each do |region|
          kinds.each do |kind|
            found, more = list_kind(environment_row, kind, region)
            entries.concat(found)
            next unless more

            gaps << "Only the first #{AwsApi::MAX_PAGES} pages of #{KIND_PLURALS.fetch(kind)} in #{region} were read."
            unread << kind
          rescue AwsApi::RateLimited => error
            gaps << "AWS asked to slow down while listing #{KIND_PLURALS.fetch(kind)} in #{region}, so the rest was not read: #{error.message}"
            return Reading.new(entries: entries, gaps: gaps, unread: kinds)
          rescue AwsApi::Error => error
            gaps << "#{KIND_PLURALS.fetch(kind)} in #{region} could not be read: #{error.message}"
            unread << kind
          end
        end
        Reading.new(entries: entries, gaps: gaps, unread: unread.uniq)
      end

      def list_kind(environment_row, kind, region)
        case kind
        when SERVICE then ecs_services(environment_row, region)
        when FUNCTION then lambda_functions(environment_row, region)
        when INSTANCE then ec2_instances(environment_row, region)
        else rds_databases(environment_row, region)
        end
      end

      def ecs_services(environment_row, region)
        clusters, more = api(environment_row).all(:ecs, region, :list_clusters, {}, :cluster_arns)
        entries = clusters.flat_map do |cluster|
          arns, cut = api(environment_row).all(:ecs, region, :list_services, { cluster: cluster }, :service_arns)
          more ||= cut
          arns.each_slice(SERVICES_PER_CALL).flat_map do |slice|
            Array(api(environment_row).call(:ecs, region, :describe_services, cluster: cluster, services: slice)[:services]).map { |service| service_entry(service, region) }
          end
        end
        [ entries, more ]
      end

      def service_entry(service, region)
        primary = Array(service[:deployments]).find { |deployment| deployment[:status] == "PRIMARY" } || {}
        status = (primary[:rollout_state] || service[:status]).to_s.downcase.presence
        cluster = service[:cluster_arn].to_s.split("/").last
        Entry.new(kind: SERVICE, arn: service[:service_arn], name: service[:service_name], region: region, cluster: cluster, status: status,
                  details: { "region" => region, "type" => service[:launch_type] || "capacity provider", "instances" => service[:desired_count],
                             "cluster" => cluster, "task_definition" => family_revision(service[:task_definition]) }.compact)
      end

      def lambda_functions(environment_row, region)
        functions, more = api(environment_row).all(:lambda, region, :list_functions, {}, :functions)
        [ functions.map { |function| function_entry(function, region) }, more ]
      end

      # Failed when the function cannot run or its last change failed, and Lambda's own state otherwise.
      def function_entry(function, region)
        failed = function[:state] == "Failed" || function[:last_update_status] == "Failed"
        Entry.new(kind: FUNCTION, arn: function[:function_arn], name: function[:function_name], region: region,
                  status: failed ? "failed" : function[:state].to_s.downcase.presence,
                  details: { "region" => region, "type" => function[:runtime] || function[:package_type] }.compact)
      end

      def ec2_instances(environment_row, region)
        filters = [ { name: "instance-state-name", values: LIVE_INSTANCE_STATES } ]
        reservations, more = api(environment_row).all(:ec2, region, :describe_instances, { filters: filters }, :reservations)
        entries = reservations.flat_map do |reservation|
          Array(reservation[:instances]).map { |instance| instance_entry(instance, reservation[:owner_id], region) }
        end
        [ entries, more ]
      end

      # DescribeInstances returns no ARN, so it is written in the form AWS's service authorization reference gives for an
      # instance.
      def instance_entry(instance, owner, region)
        name = Array(instance[:tags]).find { |tag| tag[:key] == "Name" }&.dig(:value).presence || instance[:instance_id]
        arn = "arn:#{AwsApi.partition_of(region) || CONSOLE_PARTITION}:ec2:#{region}:#{owner}:instance/#{instance[:instance_id]}"
        Entry.new(kind: INSTANCE, arn: arn, name: name, region: region, status: instance.dig(:state, :name),
                  details: { "region" => region, "type" => instance[:instance_type], "instance_id" => instance[:instance_id] }.compact)
      end

      def rds_databases(environment_row, region)
        databases, more = api(environment_row).all(:rds, region, :describe_db_instances, {}, :db_instances)
        [ databases.map { |database| database_entry(database, region) }, more ]
      end

      def database_entry(database, region)
        Entry.new(kind: DATABASE, arn: database[:db_instance_arn], name: database[:db_instance_identifier], region: region,
                  status: database[:db_instance_status],
                  details: { "region" => region, "engine" => [ database[:engine], database[:engine_version] ].compact.join(" ").presence,
                             "type" => database[:db_instance_class], "cluster" => database[:db_cluster_identifier] }.compact)
      end

      # The resource a tool was asked about, from its ARN when that says enough, and otherwise by name from what the
      # connection lists.
      def find_resource(environment_row, asked)
        wanted = asked.to_s.strip
        fail!("Say which resource, by its name or ARN. list_resources shows them.") if wanted.empty?

        direct = entry_from_arn(wanted, environment_row)
        return direct if direct

        found = inventory(environment_row, kinds: KIND_NAMES.keys, regions: regions(environment_row)).entries.select do |entry|
          [ entry.arn, entry.name, entry.details["instance_id"] ].compact.include?(wanted)
        end
        fail!("Nothing called #{wanted} in #{regions(environment_row).join(', ')}. list_resources shows what there is.") if found.empty?
        return found.first if found.one?

        fail!("More than one resource is called #{wanted}: #{found.map { |entry| "#{KIND_NAMES.fetch(entry.kind)} #{entry.arn}" }.join('; ')}. Name it by its ARN.")
      end

      # An ARN in the forms ECS, Lambda, EC2 and RDS document, for a region this connection reads. An ECS service ARN
      # without its cluster, the older form, is found by listing instead.
      def entry_from_arn(arn, environment_row)
        parts = arn.to_s.match(ARN)
        return unless parts

        region = parts[:region]
        fail!("#{arn} is in #{region}, which this connection does not read. Add the region on the connection to reach it.") if regions(environment_row).exclude?(region)

        resource = parts[:resource]
        case parts[:service]
        when "ecs"
          _, cluster, name = resource.split("/")
          Entry.new(kind: SERVICE, arn: arn, name: name, region: region, cluster: cluster) if resource.start_with?("service/") && name
        when "lambda"
          name = resource.delete_prefix("function:").split(":").first
          Entry.new(kind: FUNCTION, arn: arn.split(":").first(7).join(":"), name: name, region: region) if resource.start_with?("function:")
        when "ec2"
          id = resource.delete_prefix("instance/")
          Entry.new(kind: INSTANCE, arn: arn, name: id, region: region, details: { "instance_id" => id }) if resource.start_with?("instance/")
        when "rds"
          Entry.new(kind: DATABASE, arn: arn, name: resource.delete_prefix("db:"), region: region) if resource.start_with?("db:")
        end
      end

      def ecs_service!(environment_row, asked, what)
        entry = find_resource(environment_row, asked)
        return entry if entry.kind == SERVICE

        fail!("#{entry.name} is #{KIND_ARTICLED.fetch(entry.kind)}, and only ECS services #{what} here.")
      end

      def describe_service(environment_row, entry)
        services = api(environment_row).call(:ecs, entry.region, :describe_services, cluster: entry.cluster, services: [ entry.arn ])[:services]
        Array(services).first || fail!("ECS has no service #{entry.arn}. list_resources shows what there is.")
      end

      def task_definition(environment_row, entry, arn)
        api(environment_row).call(:ecs, entry.region, :describe_task_definition, task_definition: arn)[:task_definition] || {}
      end

      def service_lines(environment_row, entry)
        service = describe_service(environment_row, entry)
        definition = task_definition(environment_row, entry, service[:task_definition])
        [
          "#{service[:service_name]}, ECS service in cluster #{entry.cluster}, #{entry.region}, #{service[:launch_type] || 'capacity provider'}, status #{service[:status]}",
          "Tasks: #{service[:running_count]} running, #{service[:pending_count]} pending, #{service[:desired_count]} wanted",
          "Task definition: #{family_revision(service[:task_definition])}, #{definition[:cpu] || '?'} CPU units, #{definition[:memory] || '?'} MiB",
          deployment_lines(service),
          breaker_line(service[:deployment_configuration]),
          container_lines(definition),
          load_balancer_line(service),
          ("Health check grace period: #{service[:health_check_grace_period_seconds]}s" if service[:health_check_grace_period_seconds]),
          event_lines(service)
        ]
      end

      def task_line(task)
        containers = Array(task[:containers]).map do |container|
          [ container[:name], container[:last_status].to_s.downcase, ("exit code #{container[:exit_code]}" unless container[:exit_code].nil?),
            container[:reason].presence ].compact.join(" ")
        end
        [ task[:task_arn].to_s.split("/").last, task[:last_status].to_s.downcase, ("health #{task[:health_status].to_s.downcase}" if task[:health_status].present?),
          "task definition #{family_revision(task[:task_definition_arn])}", "started #{time(task[:started_at] || task[:created_at])}",
          ("stopped #{time(task[:stopped_at])}" if task[:stopped_at]), ("#{task[:stop_code]}: #{task[:stopped_reason]}" if task[:stopped_reason].present?),
          ("containers #{containers.join('; ')}" if containers.any?) ].compact.join(", ")
      end

      def deployment_lines(service)
        rows = Array(service[:deployments]).map do |deployment|
          [ deployment[:status].to_s.downcase, "task definition #{family_revision(deployment[:task_definition])}",
            "rollout #{deployment[:rollout_state].to_s.downcase.presence || 'unknown'}#{": #{deployment[:rollout_state_reason]}" if deployment[:rollout_state_reason].present?}",
            "#{deployment[:running_count]} of #{deployment[:desired_count]} running", ("#{deployment[:failed_tasks]} tasks failed to start" if deployment[:failed_tasks].to_i.positive?),
            "since #{time(deployment[:created_at])}" ].compact.join(", ")
        end
        "Deployments:\n#{rows.join("\n")}" if rows.any?
      end

      def breaker_line(configuration)
        breaker = configuration.to_h[:deployment_circuit_breaker]
        return "Deployment circuit breaker: off, so a deployment whose tasks keep failing is not stopped or rolled back by ECS." unless breaker&.dig(:enable)

        "Deployment circuit breaker: on, #{breaker[:rollback] ? 'rolls back' : 'stops without rolling back'} a deployment whose tasks keep failing"
      end

      # What each container runs and how it is checked. Environment variables and secrets are named, never shown.
      def container_lines(definition)
        rows = Array(definition[:container_definitions]).map do |container|
          check = container[:health_check]
          logging = container[:log_configuration]
          [
            "#{container[:name]}: #{container[:image]}#{', essential' if container[:essential]}",
            ("ports #{Array(container[:port_mappings]).map { |port| "#{port[:container_port]}/#{port[:protocol]}" }.join(' ')}" if container[:port_mappings].present?),
            (check ? "health check #{Array(check[:command]).join(' ')}, every #{check[:interval] || 30}s, #{check[:retries] || 3} retries" : "no container health check"),
            ("logs #{logging[:log_driver]}#{" to #{logging.dig(:options, 'awslogs-group')}" if logging.dig(:options, 'awslogs-group')}" if logging),
            ("environment variables #{Array(container[:environment]).map { |variable| variable[:name] }.join(' ')}" if container[:environment].present?),
            ("secrets #{Array(container[:secrets]).map { |secret| secret[:name] }.join(' ')}" if container[:secrets].present?)
          ].compact.join(", ")
        end
        "Containers:\n#{rows.join("\n")}" if rows.any?
      end

      def load_balancer_line(service)
        groups = Array(service[:load_balancers]).filter_map { |balancer| balancer[:target_group_arn] || balancer[:load_balancer_name] }
        "Load balancer target groups: #{groups.join(', ')}" if groups.any?
      end

      def event_lines(service)
        events = Array(service[:events]).first(EVENTS_SHOWN).map { |event| "#{time(event[:created_at])} #{event[:message]}" }
        "Latest events, newest first:\n#{events.join("\n")}" if events.any?
      end

      def function_lines(environment_row, entry)
        function = api(environment_row).call(:lambda, entry.region, :get_function_configuration, function_name: entry.name)
        aliases = api(environment_row).call(:lambda, entry.region, :list_aliases, function_name: entry.name)[:aliases]
        [
          "#{function[:function_name]}, Lambda function in #{entry.region}, #{function[:runtime] || function[:package_type]}, handler #{function[:handler] || 'none'}",
          "State: #{function[:state]}#{": #{function[:state_reason]}" if function[:state_reason].present?}",
          "Last update: #{function[:last_update_status]}#{": #{function[:last_update_status_reason]}" if function[:last_update_status_reason].present?}, at #{function[:last_modified]}",
          "Memory #{function[:memory_size]} MB, timeout #{function[:timeout]}s, #{Array(function[:architectures]).join(' ')}#{", ephemeral storage #{function.dig(:ephemeral_storage, :size)} MB" if function[:ephemeral_storage]}",
          "Code: version #{function[:version]}, sha256 #{function[:code_sha_256]}",
          ("Logs go to #{function.dig(:logging_config, :log_group)}" if function.dig(:logging_config, :log_group)),
          ("In a VPC, #{Array(function.dig(:vpc_config, :subnet_ids)).size} subnets. A function in a VPC reaches the internet only through a NAT gateway." if function.dig(:vpc_config, :vpc_id).present?),
          ("Failed asynchronous events go to #{function.dig(:dead_letter_config, :target_arn)}" if function.dig(:dead_letter_config, :target_arn)),
          ("Environment variables: #{function.dig(:environment, :variables).to_h.keys.join(' ')}" if function.dig(:environment, :variables).present?),
          alias_line(aliases)
        ]
      end

      def alias_line(aliases)
        return "Aliases: none, so traffic reaches $LATEST or a version by number, and there is no alias to roll back." if aliases.blank?

        rows = aliases.map do |each|
          weights = each.dig(:routing_config, :additional_version_weights).to_h.map { |version, weight| "#{(weight * 100).round}% to #{version}" }
          "#{each[:name]} points at version #{each[:function_version]}#{" with #{weights.join(' and ')}" if weights.any?}"
        end
        "Aliases: #{rows.join('; ')}"
      end

      def instance_lines(environment_row, entry)
        id = entry.details["instance_id"] || entry.arn.split("/").last
        reservations = api(environment_row).call(:ec2, entry.region, :describe_instances, instance_ids: [ id ])[:reservations]
        instance = Array(reservations).flat_map { |reservation| Array(reservation[:instances]) }.first || fail!("EC2 has no instance #{id}.")
        status = Array(api(environment_row).call(:ec2, entry.region, :describe_instance_status, instance_ids: [ id ], include_all_instances: true)[:instance_statuses]).first || {}
        events = Array(status[:events]).map { |event| "#{event[:code]} #{event[:description]} from #{time(event[:not_before])}" }
        [
          "#{entry.name} (#{id}), EC2 instance in #{entry.region}, #{instance[:instance_type]}, #{instance[:placement].to_h[:availability_zone]}",
          "State: #{instance.dig(:state, :name)}#{", #{instance.dig(:state_reason, :message)}" if instance.dig(:state_reason, :message).present?}, launched #{time(instance[:launch_time])}",
          "Status checks: system #{status.dig(:system_status, :status) || 'not reported'}, instance #{status.dig(:instance_status, :status) || 'not reported'}" \
          "#{", attached EBS #{status.dig(:attached_ebs_status, :status)}" if status.dig(:attached_ebs_status, :status)}",
          ("Scheduled events: #{events.join('; ')}" if events.any?),
          "Image #{instance[:image_id]}#{", platform #{instance[:platform_details]}" if instance[:platform_details]}"
        ]
      end

      def database_lines(environment_row, entry)
        database = Array(api(environment_row).call(:rds, entry.region, :describe_db_instances, db_instance_identifier: entry.name)[:db_instances]).first
        fail!("RDS has no database #{entry.name}.") unless database

        pending = database[:pending_modified_values].to_h.compact.reject { |_, value| value.respond_to?(:empty?) && value.empty? }
        events = Array(api(environment_row).call(:rds, entry.region, :describe_events, source_identifier: entry.name, source_type: "db-instance",
                                                  duration: 24 * 60, max_records: EVENTS_SHOWN * 2)[:events])
        [
          "#{entry.name}, RDS database in #{entry.region}, #{database[:engine]} #{database[:engine_version]}, #{database[:db_instance_class]}",
          "Status: #{database[:db_instance_status]}#{", in cluster #{database[:db_cluster_identifier]}" if database[:db_cluster_identifier]}",
          "Storage: #{database[:allocated_storage]} GiB #{database[:storage_type]}#{", grows to #{database[:max_allocated_storage]} GiB" if database[:max_allocated_storage]}",
          "Multi-AZ #{database[:multi_az] ? 'on' : 'off'}, in #{database[:availability_zone]}, publicly accessible #{database[:publicly_accessible] ? 'yes' : 'no'}",
          "Backups kept #{database[:backup_retention_period]} days, restorable to #{time(database[:latest_restorable_time])}",
          ("Read replicas: #{Array(database[:read_replica_db_instance_identifiers]).join(', ')}" if database[:read_replica_db_instance_identifiers].present?),
          ("Replica of #{database[:read_replica_source_db_instance_identifier]}" if database[:read_replica_source_db_instance_identifier]),
          ("Pending changes: #{pending.map { |name, value| "#{name} #{value}" }.join(', ')}" if pending.any?),
          "Logs exported to CloudWatch: #{Array(database[:enabled_cloudwatch_logs_exports]).join(', ').presence || 'none'}",
          ("Events in the last day, newest first:\n#{events.sort_by { |event| event[:date] || Time.at(0) }.reverse.first(EVENTS_SHOWN).map { |event| "#{time(event[:date])} #{event[:message]}" }.join("\n")}" if events.any?)
        ]
      end

      # Where a resource's logs are in CloudWatch Logs, as the region, the log groups and, for an ECS service, the log
      # stream prefixes its containers write under (awslogs-stream-prefix/container), since a group can be shared.
      def log_source(environment_row, entry)
        case entry.kind
        when SERVICE then service_log_source(environment_row, entry)
        when FUNCTION
          function = api(environment_row).call(:lambda, entry.region, :get_function_configuration, function_name: entry.name)
          [ entry.region, [ function.dig(:logging_config, :log_group).presence || "/aws/lambda/#{entry.name}" ], [] ]
        when DATABASE
          database = Array(api(environment_row).call(:rds, entry.region, :describe_db_instances, db_instance_identifier: entry.name)[:db_instances]).first || {}
          exported = Array(database[:enabled_cloudwatch_logs_exports])
          fail!("#{entry.name} exports no logs to CloudWatch Logs. Turn on log exports for it in RDS to read them here.") if exported.empty?

          [ entry.region, exported.map { |type| "/aws/rds/instance/#{entry.name}/#{type}" }, [] ]
        else
          fail!("An EC2 instance sends no logs to CloudWatch Logs by itself. When the CloudWatch agent writes its logs, " \
                "read them with logs_insights_query on the agent's log group.")
        end
      end

      def service_log_source(environment_row, entry)
        definition = task_definition(environment_row, entry, describe_service(environment_row, entry)[:task_definition])
        logged = Array(definition[:container_definitions]).select { |container| container.dig(:log_configuration, :log_driver) == AWSLOGS }
        if logged.empty?
          drivers = Array(definition[:container_definitions]).filter_map { |container| container.dig(:log_configuration, :log_driver) }.uniq
          fail!("#{entry.name} does not send its logs to CloudWatch Logs#{" (it uses #{drivers.join(', ')})" if drivers.any?}, so they cannot be read here.")
        end

        options = logged.map { |container| container.dig(:log_configuration, :options).to_h }
        region = options.filter_map { |option| option["awslogs-region"] }.first || entry.region
        groups = options.filter_map { |option| option["awslogs-group"] }.uniq
        fail!("#{entry.name}'s task definition names no awslogs-group, so its log group is not known.") if groups.empty?

        streams = logged.zip(options).filter_map do |container, option|
          "#{option['awslogs-stream-prefix']}/#{container[:name]}/" if option["awslogs-stream-prefix"].present?
        end
        [ region, groups, streams.uniq.select { |prefix| prefix.match?(SAFE_NAME) } ]
      end

      # A Logs Insights query for the lines asked, newest first. Text goes inside double quotes and a regular expression
      # inside slashes, as AWS's filter command documents. Logs Insights documents no way to escape a quote or a
      # backslash, so text holding one is refused.
      def log_query(arguments, streams, limit)
        text, regex, exclude = arguments.values_at("text", "regex", "exclude").map(&:presence)
        [ text, exclude ].compact.each do |value|
          fail!("Logs Insights has no documented way to search for a double quote or a backslash. Search for text without one.") if value.match?(UNQUOTABLE)
        end
        fail!("Write a forward slash in regex as \\/, since Logs Insights ends the expression at the first one.") if regex&.match?(UNESCAPED_SLASH)

        filters = []
        filters << "filter #{streams.map { |prefix| "@logStream like \"#{prefix}\"" }.join(' or ')}" if streams.any?
        filters << "filter @message like \"#{text}\"" if text
        filters << "filter @message not like \"#{exclude}\"" if exclude
        filters << "filter @message like /#{regex}/" if regex
        [ "fields @timestamp, @logStream, @message", *filters, "sort @timestamp desc", "limit #{limit}" ].join(" | ")
      end

      # Starts the query and waits for Logs Insights to finish it. A query still running when the wait ends is stopped,
      # so it does not keep scanning, and the agent is told to narrow it.
      def run_query(environment_row, region, groups, query, started, ended, limit)
        logs = api(environment_row)
        id = logs.call(:logs, region, :start_query, log_group_names: groups, query_string: query, start_time: started.to_i, end_time: ended.to_i, limit: limit)[:query_id]
        deadline = QUERY_WAIT.seconds.from_now
        loop do
          answer = logs.call(:logs, region, :get_query_results, query_id: id)
          status = answer[:status].to_s
          return Array(answer[:results]).map { |row| Array(row).to_h { |cell| [ cell[:field], cell[:value] ] }.except("@ptr") } if status == "Complete"
          fail!("Logs Insights ended the query as #{status}. Check the query and the log groups, then try again.") if QUERY_DONE.include?(status)

          if Time.current > deadline
            begin
              logs.call(:logs, region, :stop_query, query_id: id)
            rescue AwsApi::Error
              nil
            end
            fail!("Logs Insights did not finish within #{QUERY_WAIT} seconds. Narrow the range or filter, then try again.")
          end
          sleep QUERY_POLL
        end
      end

      # Logs Insights writes @timestamp in UTC without a zone, such as 2026-10-01 12:00:00.000.
      def insights_time(value)
        Time.find_zone("UTC").parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      # A period AWS accepts (a multiple of 60) that keeps a chart near a few hundred points.
      def period_for(started, ended)
        minutes = (ended - started) / 60
        return 60 if minutes <= 180
        return 300 if minutes <= 24 * 60

        3600
      end

      # Each metric's points in time order, as Firefight shows them: scaled to their unit and a sum per period made per minute.
      def metric_data(environment_row, entry, names, started, ended, period)
        dimensions = dimensions_of(entry)
        queries = names.each_with_index.map do |name, index|
          metric = METRICS.fetch(entry.kind).fetch(name)
          { id: "m#{index}", metric_stat: { metric: { namespace: NAMESPACES.fetch(entry.kind), metric_name: name, dimensions: dimensions },
                                            period: period, stat: metric.stat }, return_data: true }
        end
        answer = api(environment_row).call(:cloudwatch, entry.region, :get_metric_data, metric_data_queries: queries, start_time: started, end_time: ended)
        names.each_with_index.to_h do |name, index|
          metric = METRICS.fetch(entry.kind).fetch(name)
          result = Array(answer[:metric_data_results]).find { |each| each[:id] == "m#{index}" } || {}
          factor = metric.scale * (metric.summed ? 60.0 / period : 1)
          points = Array(result[:timestamps]).zip(Array(result[:values])).filter_map { |at, value| [ at.utc, value.to_f * factor ] if at && value }
          [ name, points.sort_by(&:first) ]
        end
      end

      # The dimensions each namespace's metrics page gives for one resource.
      def dimensions_of(entry)
        case entry.kind
        when SERVICE then [ { name: "ClusterName", value: entry.cluster }, { name: "ServiceName", value: entry.name } ]
        when FUNCTION then [ { name: "FunctionName", value: entry.name } ]
        when INSTANCE then [ { name: "InstanceId", value: entry.details["instance_id"] || entry.arn.split("/").last } ]
        else [ { name: "DBInstanceIdentifier", value: entry.name } ]
        end
      end

      def per_minute(unit) = unit == COUNT ? PER_MINUTE : "#{unit} #{PER_MINUTE}"

      def service_deployments(environment_row, entry, limit)
        aws = api(environment_row)
        recent = Array(deployment_history(aws, entry)).sort_by { |deployment| deployment[:created_at] || Time.at(0) }.reverse.first(limit)
        described = recent.map { |deployment| deployment[:service_deployment_arn] }.each_slice(ARNS_PER_CALL).flat_map do |arns|
          Array(aws.call(:ecs, entry.region, :describe_service_deployments, service_deployment_arns: arns)[:service_deployments])
        end.index_by { |deployment| deployment[:service_deployment_arn] }
        revisions = recent.filter_map { |deployment| deployment[:target_service_revision_arn] }.uniq.each_slice(ARNS_PER_CALL).flat_map do |arns|
          Array(aws.call(:ecs, entry.region, :describe_service_revisions, service_revision_arns: arns)[:service_revisions])
        end.index_by { |revision| revision[:service_revision_arn] }
        service = describe_service(environment_row, entry)
        running = family_revision(service[:task_definition])
        rows = recent.map { |deployment| deployment_line(deployment, described[deployment[:service_deployment_arn]] || {}, revisions[deployment[:target_service_revision_arn]] || {}) }
        current = deployment_lines(service)
        family = running.to_s.split(":").first
        earlier = aws.call(:ecs, entry.region, :list_task_definitions, family_prefix: family, sort: "DESC", max_results: REVISIONS_SHOWN)[:task_definition_arns]
        choices = Array(earlier).map { |arn| family_revision(arn) }.select { |each| each.split(":").first == family }
        text = if rows.any?
          "Latest #{rows.size} deployments of #{entry.name}, newest first.\n#{rows.join("\n")}"
        else
          "ECS has no deployment history for #{entry.name}. It keeps the last 90 days of deployments made on or after " \
            "October 25, 2024.#{"\n#{current}" if current}"
        end
        Telemetry.result("#{text}\nIt runs #{running}. A rollback takes a revision of #{family}: #{choices.map { |each| each == running ? "#{each} (running)" : each }.join(', ')}.",
                         link: resource_link(entry))
      end

      # A refusal other than a permission or a slow down reads as no history, and the current deployments are shown instead.
      def deployment_history(aws, entry)
        aws.call(:ecs, entry.region, :list_service_deployments, cluster: entry.cluster, service: entry.arn, max_results: 100)[:service_deployments]
      rescue AwsApi::Denied, AwsApi::RateLimited
        raise
      rescue AwsApi::Error
        []
      end

      def deployment_line(listed, described, revision)
        rollback = described[:rollback]
        breaker = described[:deployment_circuit_breaker]
        images = Array(revision[:container_images]).map { |image| "#{image[:container_name]} #{image[:image]}" }
        [ time(listed[:started_at] || listed[:created_at]), listed[:status].to_s.downcase, ("task definition #{family_revision(revision[:task_definition])}" if revision[:task_definition]),
          ("images #{images.join(', ')}" if images.any?), listed[:status_reason].presence,
          ("rolled back at #{time(rollback[:started_at])}: #{rollback[:reason]}" if rollback),
          ("circuit breaker #{breaker[:status].to_s.downcase}, #{breaker[:failure_count]} of #{breaker[:threshold]} failed tasks" if breaker && breaker[:status].present?),
          ("finished #{time(listed[:finished_at])}" if listed[:finished_at]) ].compact.join(", ")
      end

      def function_versions(environment_row, entry, limit)
        aws = api(environment_row)
        # Lambda lists versions oldest first, so every page is read to reach the newest.
        versions, = aws.all(:lambda, entry.region, :list_versions_by_function, { function_name: entry.name }, :versions, max_pages: VERSION_PAGES)
        aliases = Array(aws.call(:lambda, entry.region, :list_aliases, function_name: entry.name)[:aliases])
        pointed = aliases.group_by { |each| each[:function_version] }
        published = versions.reject { |version| version[:version] == "$LATEST" }.sort_by { |version| -version[:version].to_i }.first(limit)
        link = resource_link(entry)
        return Telemetry.result("#{entry.name} has no published versions, so it runs $LATEST and has nothing to roll back to.", link: link) if published.empty?

        rows = published.map do |version|
          names = Array(pointed[version[:version]]).map { |each| each[:name] }
          [ "version #{version[:version]}", "last modified #{version[:last_modified]}", ("\"#{version[:description]}\"" if version[:description].present?),
            "code sha256 #{version[:code_sha_256].to_s.first(12)}", ("alias #{names.join(', ')}" if names.any?) ].compact.join(", ")
        end
        how = aliases.size > 1 ? "A rollback takes alias:version, such as #{aliases.first[:name]}:#{published.last[:version]}" : "A rollback takes a version"
        Telemetry.result("Latest #{rows.size} versions of #{entry.name}, newest first. #{how}.\n#{rows.join("\n")}\n#{alias_line(aliases)}", link: link)
      end

      # Only a revision of the family the service runs, so a rollback can never swap in a different application.
      def rollback_service(environment_row, entry, to)
        parts = to.match(TASK_DEFINITION) || to.match(TASK_DEFINITION_ARN)
        fail!("to must be a task definition revision, such as web:41, as list_deployments shows it.") unless parts

        service = describe_service(environment_row, entry)
        running = family_revision(service[:task_definition])
        family = running.to_s.split(":").first
        fail!("#{entry.name} runs the #{family} family, so roll it back to a revision of #{family}, such as #{family}:#{parts[:revision]}.") if parts[:family] != family
        target = "#{family}:#{parts[:revision]}"
        fail!("#{entry.name} already runs #{target}.") if target == running

        changing(entry) do
          api(environment_row).call(:ecs, entry.region, :update_service, cluster: entry.cluster, service: entry.arn, task_definition: target)
        end
        Telemetry.result("#{entry.name} is rolling out #{target} in place of #{running}. Undo by rolling back to #{running}.", link: resource_link(entry))
      end

      # Lambda moves traffic back by pointing an alias at an earlier version. A function with no alias has nothing to move.
      def rollback_function(environment_row, entry, to)
        parts = to.match(LAMBDA_TARGET)
        fail!("to must be a version, or alias:version such as live:12, as list_deployments shows it.") unless parts

        aliases = Array(api(environment_row).call(:lambda, entry.region, :list_aliases, function_name: entry.name)[:aliases])
        fail!("#{entry.name} has no alias, so there is no traffic to move back. Callers reach $LATEST or a version by number.") if aliases.empty?
        chosen = parts[:alias] ? aliases.find { |each| each[:name] == parts[:alias] } : (aliases.first if aliases.one?)
        unless chosen
          names = aliases.map { |each| each[:name] }
          fail!(parts[:alias] ? "#{entry.name} has no alias #{parts[:alias]}. It has #{names.join(', ')}." : "#{entry.name} has more than one alias (#{names.join(', ')}), so say which, as alias:version.")
        end
        before = chosen[:function_version]
        fail!("#{chosen[:name]} already points at version #{parts[:version]}.") if before == parts[:version]

        changing(entry) do
          api(environment_row).call(:lambda, entry.region, :update_alias, function_name: entry.name, name: chosen[:name], function_version: parts[:version])
        end
        Telemetry.result("#{entry.name}'s alias #{chosen[:name]} now points at version #{parts[:version]} in place of #{before}. " \
                         "Undo by pointing it back at #{before}.", link: resource_link(entry))
      end

      # A change the keys' policy refuses says what to allow, since that is the workspace's to fix in AWS. AWS's own
      # refusal names the action it denied.
      def changing(entry)
        yield
      rescue AwsApi::Denied => error
        fail!("#{error.message.delete_suffix('.')}. The access key's policy does not allow this change to #{entry.name}. Allow the " \
              "action AWS names in the policy of the access key's IAM user, then run it again.")
      end

      def family_revision(arn) = arn.to_s.split("/").last.presence

      def time(value) = value.respond_to?(:utc) ? value.utc.iso8601 : value.to_s.presence || "unknown"

      # Pages in the AWS console, on the regional console host AWS's console guide gives, at the service paths AWS's own
      # guides link to. Only for the aws partition, the one those addresses are documented for.
      def resource_link(entry)
        case entry.kind
        when SERVICE then console_link(entry.region, "ecs/v2")
        when FUNCTION then console_link(entry.region, "lambda/home", "/functions")
        when INSTANCE then console_link(entry.region, "ec2/")
        else console_link(entry.region, "rds/")
        end
      end

      # CloudWatch's metrics page opened on the resource's namespace, in the form Lambda's guide links to (namespace=~'AWS*2fLambda).
      def metrics_link(entry)
        console_link(entry.region, "cloudwatch/home", "metricsV2:graph=~();namespace=~'#{NAMESPACES.fetch(entry.kind).sub('/', '*2f')}")
      end

      def console_link(region, path, fragment = nil)
        return nil unless region && AwsApi.partition_of(region) == CONSOLE_PARTITION

        Telemetry::Link.new(provider: PROVIDER, url: "https://#{region}.console.aws.amazon.com/#{path}?region=#{region}#{"##{fragment}" if fragment}")
      end
    end
  end
end
