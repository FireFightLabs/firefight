module Integrations
  module Packs
    class Azure < NativePack
      # The metrics the pack reads from Azure Monitor, by the names every capability uses. Each is a metric's name in the
      # REST API, the aggregation Azure keeps for it, and how a value becomes the unit a person reads, from Microsoft's
      # supported metrics reference (learn.microsoft.com/azure/azure-monitor/reference/supported-metrics, the pages for
      # Microsoft.Web/sites, Microsoft.Web/serverfarms, Microsoft.App/containerapps, Microsoft.Sql/servers/databases and
      # Microsoft.DBforPostgreSQL/flexibleServers).
      module Metrics
        # on_plan reads the App Service plan the app runs on, since a site keeps no CPU percentage of its own. status
        # keeps only the series of one status code class, from the statusCodeCategory dimension.
        Metric = Data.define(:name, :aggregation, :unit, :title, :scale, :rate, :on_plan, :status) do
          def initialize(scale: 1, rate: nil, on_plan: false, status: nil, **) = super
        end

        AVERAGE = "average".freeze
        TOTAL = "total".freeze
        PERCENT = "%".freeze
        MEGABYTES = "MB".freeze
        COUNT = "count".freeze
        PER_MINUTE = "per minute".freeze
        BYTES_PER_SECOND = "bytes/s".freeze
        CPU_SECONDS = "CPU seconds per minute".freeze
        MEGABYTE = 1.0 / 1_048_576
        STATUS_DIMENSION = "statusCodeCategory".freeze

        SITE = {
          "cpu" => Metric.new(name: "CpuPercentage", aggregation: AVERAGE, unit: PERCENT, title: "CPU of its App Service plan", on_plan: true),
          "memory" => Metric.new(name: "MemoryWorkingSet", aggregation: AVERAGE, unit: MEGABYTES, scale: MEGABYTE, title: "Memory working set"),
          "cpu_time" => Metric.new(name: "CpuTime", aggregation: TOTAL, unit: CPU_SECONDS, rate: :minute, title: "CPU time"),
          "requests" => Metric.new(name: "Requests", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "Requests"),
          "http_4xx" => Metric.new(name: "Http4xx", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "4xx responses"),
          "http_5xx" => Metric.new(name: "Http5xx", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "5xx responses"),
          "network_in" => Metric.new(name: "BytesReceived", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network in"),
          "network_out" => Metric.new(name: "BytesSent", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network out")
        }.freeze
        CONTAINER = {
          "cpu" => Metric.new(name: "CpuPercentage", aggregation: AVERAGE, unit: PERCENT, title: "CPU"),
          "memory" => Metric.new(name: "MemoryPercentage", aggregation: AVERAGE, unit: PERCENT, title: "Memory"),
          "requests" => Metric.new(name: "Requests", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "Requests"),
          "http_4xx" => Metric.new(name: "Requests", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "4xx responses", status: "4"),
          "http_5xx" => Metric.new(name: "Requests", aggregation: TOTAL, unit: PER_MINUTE, rate: :minute, title: "5xx responses", status: "5"),
          "network_in" => Metric.new(name: "RxBytes", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network in"),
          "network_out" => Metric.new(name: "TxBytes", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network out")
        }.freeze
        SQL = {
          "cpu" => Metric.new(name: "cpu_percent", aggregation: AVERAGE, unit: PERCENT, title: "CPU"),
          "disk" => Metric.new(name: "storage_percent", aggregation: AVERAGE, unit: PERCENT, title: "Storage used")
        }.freeze
        POSTGRES = {
          "cpu" => Metric.new(name: "cpu_percent", aggregation: AVERAGE, unit: PERCENT, title: "CPU"),
          "memory" => Metric.new(name: "memory_percent", aggregation: AVERAGE, unit: PERCENT, title: "Memory"),
          "disk" => Metric.new(name: "storage_percent", aggregation: AVERAGE, unit: PERCENT, title: "Storage used"),
          "tcp_connections" => Metric.new(name: "active_connections", aggregation: AVERAGE, unit: COUNT, title: "Active connections"),
          "network_in" => Metric.new(name: "network_bytes_ingress", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network in"),
          "network_out" => Metric.new(name: "network_bytes_egress", aggregation: TOTAL, unit: BYTES_PER_SECOND, rate: :second, title: "Network out")
        }.freeze
        BY_TYPE = { TYPE_WEB => SITE, TYPE_FUNCTION => SITE, TYPE_CONTAINER => CONTAINER, TYPE_SQL => SQL, TYPE_POSTGRES => POSTGRES }.freeze
        DEFAULTS = {
          TYPE_WEB => %w[requests http_5xx cpu memory], TYPE_FUNCTION => %w[requests http_5xx memory], TYPE_CONTAINER => %w[requests http_5xx cpu memory],
          TYPE_SQL => %w[cpu disk], TYPE_POSTGRES => %w[cpu memory disk tcp_connections]
        }.freeze
        # What a baseline reads for each kind, once a day over a week.
        BASELINES = {
          TYPE_WEB => %w[requests http_5xx memory], TYPE_FUNCTION => %w[requests http_5xx memory], TYPE_CONTAINER => %w[requests cpu memory],
          TYPE_SQL => %w[cpu disk], TYPE_POSTGRES => %w[cpu memory disk tcp_connections]
        }.freeze
        # The time grains Azure Monitor takes, in minutes, and how each is written.
        GRAINS = { 1 => "PT1M", 5 => "PT5M", 15 => "PT15M", 30 => "PT30M", 60 => "PT1H", 360 => "PT6H", 720 => "PT12H", 1440 => "P1D" }.freeze
        POINTS = 60

        # The metrics a resource on the map has, each by the name every capability uses, which the pack takes as is. A
        # resource is told apart by the type the map keeps in its details.
        def self.names(type) = BY_TYPE.fetch(type, SITE).keys.index_with(&:itself)

        def self.grain(started, ended)
          wanted = (ended - started) / 60.0 / POINTS
          GRAINS.find { |minutes, _| minutes >= wanted } || GRAINS.to_a.last
        end
      end
    end
  end
end
