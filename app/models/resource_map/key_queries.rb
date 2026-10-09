# The few checks worth running first on each kind of resource, such as a service's error rate and p95 latency or a
# function's throttles. Each names the capability it runs with its arguments, and a metric check the baseline it is
# read against. Whether a resource has a check is worked out live from the connections that run or watch it, so nothing
# about it is stored.
module ResourceMap::KeyQueries
  CAPABILITIES = Integrations::Capabilities
  TOOL_NAME = CAPABILITIES::KEY_QUERY_TOOL
  DEFAULT_MINUTES = CAPABILITIES::DEFAULT_MINUTES
  DEPLOYS_SHOWN = 10
  ERRORS_SHOWN = 20

  # metrics are the capability metric names that read it, in order of preference, so the first the answering connection
  # keeps is read, such as a function's invocations or its requests where its provider counts them that way.
  Check = Data.define(:key, :label, :capability, :metrics) do
    def initialize(metrics: [], **) = super

    def metric? = capability == CAPABILITIES::METRICS

    def arguments(metric, minutes)
      case capability
      when CAPABILITIES::METRICS then { "metrics" => [ metric ], "minutes" => minutes }
      when CAPABILITIES::DEPLOYS then { "limit" => DEPLOYS_SHOWN }
      when CAPABILITIES::ERRORS then { "limit" => ERRORS_SHOWN, "minutes" => minutes }
      else {}
      end
    end
  end

  CHECKS = [
    Check.new(key: "error_rate", label: "Error rate", capability: CAPABILITIES::METRICS, metrics: %w[http_5xx errors]),
    Check.new(key: "latency_p95", label: "p95 latency", capability: CAPABILITIES::METRICS, metrics: %w[latency_p95]),
    Check.new(key: "cpu", label: "CPU", capability: CAPABILITIES::METRICS, metrics: %w[cpu]),
    Check.new(key: "memory", label: "Memory", capability: CAPABILITIES::METRICS, metrics: %w[memory]),
    Check.new(key: "connections", label: "Connections", capability: CAPABILITIES::METRICS, metrics: %w[tcp_connections]),
    Check.new(key: "disk", label: "Disk", capability: CAPABILITIES::METRICS, metrics: %w[disk]),
    Check.new(key: "traffic", label: "Traffic", capability: CAPABILITIES::METRICS, metrics: %w[requests]),
    Check.new(key: "invocations", label: "Invocations", capability: CAPABILITIES::METRICS, metrics: %w[invocations requests]),
    Check.new(key: "errors", label: "Errors", capability: CAPABILITIES::METRICS, metrics: %w[errors http_5xx]),
    Check.new(key: "duration", label: "Duration", capability: CAPABILITIES::METRICS, metrics: %w[duration latency_p95]),
    Check.new(key: "throttles", label: "Throttles", capability: CAPABILITIES::METRICS, metrics: %w[throttles]),
    Check.new(key: "recent_deploys", label: "Recent deploys", capability: CAPABILITIES::DEPLOYS),
    Check.new(key: "recent_errors", label: "Recent errors", capability: CAPABILITIES::ERRORS),
    Check.new(key: "status", label: "How it stands", capability: CAPABILITIES::STATUS),
    Check.new(key: "availability", label: "Availability", capability: CAPABILITIES::STATUS),
    Check.new(key: "ci_status", label: "CI status", capability: CAPABILITIES::STATUS)
  ].index_by(&:key).freeze
  KEYS = CHECKS.keys.freeze
  DESCRIPTION = "Run one of a resource's key checks, the first things worth reading on it: a service's error rate, p95 " \
                "latency, CPU, memory and recent deploys, a database's CPU, memory, connections and disk, a function's " \
                "invocations, errors, duration and throttles, a domain's or site's availability. The answer says how the " \
                "reading compares with what is normal for it over the last week. get_resource_map lists a resource's checks " \
                "with their normal".freeze
  SCHEMA = {
    "type" => "object",
    "properties" => {
      "resource" => { "type" => "string", "description" => "The resource, by its name, its provider's id or its id on the resource map" },
      "query" => { "type" => "string", "enum" => CHECKS.keys, "description" => "Which check, one the resource's kind has" },
      "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" }
    },
    "required" => %w[resource query]
  }.freeze
  # How a person reads the metric a check with a choice of them read, such as 5xx responses for an error rate.
  METRIC_WORDS = {
    "http_5xx" => "5xx responses", "errors" => "errors", "invocations" => "invocations", "requests" => "requests",
    "duration" => "average duration", "latency_p95" => "95th percentile latency"
  }.freeze
  # The capabilities the checks read through, none of which changes anything.
  CAPABILITIES_READ = CHECKS.values.map(&:capability).uniq.freeze

  BY_KIND = {
    ResourceMap::KIND_SERVICE => %w[error_rate latency_p95 cpu memory recent_deploys],
    ResourceMap::KIND_WORKER => %w[error_rate cpu memory recent_deploys],
    ResourceMap::KIND_JOB => %w[status errors cpu memory recent_deploys],
    ResourceMap::KIND_FUNCTION => %w[invocations errors duration throttles],
    ResourceMap::KIND_DATABASE => %w[cpu memory connections disk],
    ResourceMap::KIND_BRANCH => %w[status cpu memory connections disk],
    ResourceMap::KIND_COMPUTE => %w[status cpu memory],
    ResourceMap::KIND_VIRTUAL_MACHINE => %w[status cpu memory disk],
    ResourceMap::KIND_CLUSTER => %w[status],
    ResourceMap::KIND_DOMAIN => %w[availability],
    ResourceMap::KIND_SITE => %w[availability recent_deploys],
    ResourceMap::KIND_ZONE => %w[availability traffic error_rate],
    ResourceMap::KIND_REPOSITORY => %w[ci_status recent_deploys],
    ResourceMap::KIND_QUEUE => %w[recent_errors]
  }.transform_values { |keys| keys.map { |key| CHECKS.fetch(key) }.freeze }.freeze

  NO_SHARED_READ = "No connected provider says how one stands or performs through Firefight's shared reads, so it has no " \
                   "checks. Its provider's own tools still read it.".freeze
  # Why a kind has no checks, said wherever its checks would be listed.
  NONE = {
    ResourceMap::KIND_BUILD_SERVICE => "A build service only builds. Its builds are in its logs, and the services it builds have the checks.",
    ResourceMap::KIND_BUCKET => NO_SHARED_READ, ResourceMap::KIND_KV_NAMESPACE => NO_SHARED_READ,
    ResourceMap::KIND_DATABASE_PROXY => NO_SHARED_READ, ResourceMap::KIND_TUNNEL => NO_SHARED_READ,
    ResourceMap::KIND_LOAD_BALANCER => NO_SHARED_READ, ResourceMap::KIND_ORIGIN_POOL => NO_SHARED_READ,
    ResourceMap::KIND_ACCESS_APP => NO_SHARED_READ
  }.freeze

  # How a check would run on a resource now: the capability call it resolves to and the metric it reads, or why it
  # cannot run.
  Plan = Data.define(:resource, :check, :call, :metric, :refusal) do
    def available? = !call.nil?

    def arguments(minutes) = { CAPABILITIES::RESOURCE_ARG => resource.id }.merge(check.arguments(metric, minutes))

    # The normal of what the check reads, as the connection that would answer read it, or nil.
    def baseline = available? && metric ? ResourceMap::KeyQueries.baseline(call, metric) : nil

    def connection = call && call.environment_row.integration.display_name

    # Which of its metrics a check with a choice of them reads here, in words, nil for a check that has one way to read.
    def reads = check.metrics.many? && metric ? METRIC_WORDS.fetch(metric, metric) : nil
  end

  def self.for(kind) = BY_KIND.fetch(kind, [])

  # How far back a read looks, in minutes, the default when none or nonsense was asked.
  def self.minutes(value) = value.to_i.positive? ? value.to_i : DEFAULT_MINUTES

  def self.find(kind, key) = self.for(kind).find { |check| check.key == key.to_s }

  def self.none_reason(kind) = NONE[kind]

  # What run_key_query says when a resource has no check of that name.
  def self.unknown(resource, key)
    return "#{resource.name} has no checks. #{none_reason(resource.kind)}" if self.for(resource.kind).empty?

    "#{resource.name} has no #{key} check. Its checks are #{self.for(resource.kind).map(&:key).to_sentence}."
  end

  # Each metric the check reads is tried in turn, and the first a connection that runs or watches the resource keeps is
  # the one it reads. tools are the ones that may answer, every switched on tool when nil.
  def self.plan(resource, check, principal:, tools: nil)
    refusal = nil
    (check.metrics.presence || [ nil ]).each do |metric|
      given = { CAPABILITIES::RESOURCE_ARG => resource.id }.merge(check.arguments(metric, DEFAULT_MINUTES))
      call = CAPABILITIES.resolve(resource.workspace, check.capability, given, tools, principal: principal)
      return Plan.new(resource: resource, check: check, call: call, metric: metric, refusal: nil)
    rescue CAPABILITIES::Unroutable => error
      refusal ||= error.message
    end
    Plan.new(resource: resource, check: check, call: nil, metric: nil, refusal: refusal)
  end

  def self.plans(resource, principal:, tools: nil) = self.for(resource.kind).map { |check| plan(resource, check, principal: principal, tools: tools) }

  # A check as the map page lists it for principal: how it would run, and why principal may not run it, or nil.
  Listed = Data.define(:plan, :run_blocked_reason)

  # A check is planned through the tools principal may call, as running it is, and planned again through every tool
  # only when none of them answers, to say which tool it would need.
  def self.listed(resource, principal)
    callable = Hash.new { |found, capability| found[capability] = CAPABILITIES.callable(resource.workspace, capability, principal) }
    self.for(resource.kind).map do |check|
      plan = plan(resource, check, principal: principal, tools: callable[check.capability])
      plan = plan(resource, check, principal: principal) unless plan.available?
      Listed.new(plan: plan, run_blocked_reason: run_blocked_reason(plan, principal))
    end
  end

  def self.run_blocked_reason(plan, principal)
    return plan.refusal unless plan.available?

    tool = plan.call.tool
    return if tool.callable_by?(principal)

    "Running it calls #{tool.action_key} on #{tool.integration.display_name}, which you have not been granted. An admin can grant it on the Permissions page."
  end

  def self.baseline(call, metric)
    kept = CAPABILITIES.baseline_metric(call.environment_row, metric, call.resource.kind)
    kept && ResourceMap::Baseline.fresh.find_by(resource_id: call.resource.id, integration_environment_id: call.environment_row.id, metric: kept)
  end

  # The latest value of the first chart an answer drew, the highest when it has several series, with its unit.
  Reading = Data.define(:value, :unit, :series)

  def self.reading(result)
    charts = dig(dig(result, Integrations::Telemetry::STRUCTURED), Integrations::Telemetry::CHARTS)
    chart = Array(charts).first
    return unless chart

    latest = Array(dig(chart, "series")).filter_map { |series| Array(dig(series, "points")).last&.last }.grep(Numeric)
    latest.any? ? Reading.new(value: latest.max, unit: dig(chart, "unit"), series: latest.size) : nil
  end

  # How a check's answer compares with normal, in a sentence, or nil for a check that reads no metric. call is the one
  # that answered, which is the platform's when an observability tool had nothing.
  def self.verdict(check, call, metric, result)
    return unless check.metric?

    found = reading(result)
    return "No reading came back for #{metric}, so it is not compared with normal." unless found

    baseline = baseline(call, metric)
    return baseline.compared(found.value, found.unit, series: found.series) if baseline

    "Now #{ResourceMap::Baseline.amount(found.value, found.unit)}. No normal is known for it yet, since " \
      "#{call.environment_row.integration.display_name} has not read a week of #{metric} for #{call.resource.scoped_name}."
  end

  # The line an answer starts with: what was checked, through which connection, and how it compares.
  def self.headline(check, call, metric, result)
    read = "read as #{METRIC_WORDS.fetch(metric, metric)}" if metric && check.metrics.many?
    what = [ "#{check.label} of #{call.resource.scoped_name}", read, "from #{call.environment_row.integration.display_name}" ].compact.join(", ")
    [ "#{what}.", verdict(check, call, metric, result) ].compact.join(" ")
  end

  def self.dig(hash, key) = hash.is_a?(Hash) ? hash[key] || hash[key.to_sym] : nil
  private_class_method :dig
end
