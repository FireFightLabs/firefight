module Integrations
  module Packs
    class GoogleCloud < NativePack
      # The metrics the pack reads from Cloud Monitoring, by the names every capability uses.
      module Metrics
        # One metric as Cloud Monitoring keeps it: its metric type, the aligner and cross series reducer that read it (a
        # distribution takes a percentile, a count a rate, a gauge a mean), any label it is narrowed by, and how a value
        # becomes the unit a person reads. The types, kinds, units and labels are the ones Google's metrics lists give
        # (cloud.google.com/monitoring/api/metrics_gcp_p_z for Cloud Run, metrics_gcp_c for Cloud SQL and Compute Engine,
        # metrics_opsagent for the Ops Agent).
        Metric = Data.define(:type, :aligner, :reducer, :filter, :unit, :scale, :title) do
          def initialize(reducer: nil, filter: nil, scale: 1, **) = super
        end

        PERCENT = "%".freeze
        PER_SECOND = "per second".freeze
        PER_MINUTE = "per minute".freeze
        BYTES_PER_SECOND = "bytes/s".freeze
        COUNT = "count".freeze
        # Google writes a utilization as a fraction (unit 10^2.%), which a person reads as a percentage.
        FRACTION = 100

        RUN_REQUESTS = "run.googleapis.com/request_count".freeze
        RUN = {
          "cpu" => Metric.new(type: "run.googleapis.com/container/cpu/utilizations", aligner: "ALIGN_PERCENTILE_99", reducer: "REDUCE_MAX",
                              unit: PERCENT, scale: FRACTION, title: "CPU of its busiest instances"),
          "memory" => Metric.new(type: "run.googleapis.com/container/memory/utilizations", aligner: "ALIGN_PERCENTILE_99", reducer: "REDUCE_MAX",
                                 unit: PERCENT, scale: FRACTION, title: "Memory of its busiest instances"),
          "requests" => Metric.new(type: RUN_REQUESTS, aligner: "ALIGN_RATE", reducer: "REDUCE_SUM", unit: PER_SECOND, title: "Requests"),
          "http_4xx" => Metric.new(type: RUN_REQUESTS, aligner: "ALIGN_RATE", reducer: "REDUCE_SUM", filter: 'metric.labels.response_code_class="4xx"',
                                   unit: PER_SECOND, title: "4xx responses"),
          "http_5xx" => Metric.new(type: RUN_REQUESTS, aligner: "ALIGN_RATE", reducer: "REDUCE_SUM", filter: 'metric.labels.response_code_class="5xx"',
                                   unit: PER_SECOND, title: "5xx responses"),
          "network_in" => Metric.new(type: "run.googleapis.com/container/network/received_bytes_count", aligner: "ALIGN_RATE", reducer: "REDUCE_SUM",
                                     unit: BYTES_PER_SECOND, title: "Network in"),
          "network_out" => Metric.new(type: "run.googleapis.com/container/network/sent_bytes_count", aligner: "ALIGN_RATE", reducer: "REDUCE_SUM",
                                      unit: BYTES_PER_SECOND, title: "Network out"),
          # request_latencies is a distribution in ms, so its 95th percentile is read per revision and the slowest kept.
          "latency_p95" => Metric.new(type: "run.googleapis.com/request_latencies", aligner: "ALIGN_PERCENTILE_95", reducer: "REDUCE_MAX",
                                      unit: "ms", title: "Latency, 95th percentile")
        }.freeze
        # network/connections is kept only for MySQL and SQL Server, and num_backends is PostgreSQL's, one series a database.
        SQL_CONNECTIONS = Metric.new(type: "cloudsql.googleapis.com/database/network/connections", aligner: "ALIGN_MEAN", unit: COUNT, title: "Connections")
        POSTGRES_CONNECTIONS = Metric.new(type: "cloudsql.googleapis.com/database/postgresql/num_backends", aligner: "ALIGN_MEAN", reducer: "REDUCE_SUM",
                                          unit: COUNT, title: "Connections")
        SQL = {
          "cpu" => Metric.new(type: "cloudsql.googleapis.com/database/cpu/utilization", aligner: "ALIGN_MEAN", unit: PERCENT, scale: FRACTION, title: "CPU"),
          "memory" => Metric.new(type: "cloudsql.googleapis.com/database/memory/utilization", aligner: "ALIGN_MEAN", unit: PERCENT, scale: FRACTION, title: "Memory"),
          "disk" => Metric.new(type: "cloudsql.googleapis.com/database/disk/utilization", aligner: "ALIGN_MEAN", unit: PERCENT, scale: FRACTION, title: "Disk used"),
          "tcp_connections" => SQL_CONNECTIONS,
          "network_in" => Metric.new(type: "cloudsql.googleapis.com/database/network/received_bytes_count", aligner: "ALIGN_RATE", unit: BYTES_PER_SECOND, title: "Network in"),
          "network_out" => Metric.new(type: "cloudsql.googleapis.com/database/network/sent_bytes_count", aligner: "ALIGN_RATE", unit: BYTES_PER_SECOND, title: "Network out")
        }.freeze
        MACHINE = {
          "cpu" => Metric.new(type: "compute.googleapis.com/instance/cpu/utilization", aligner: "ALIGN_MEAN", unit: PERCENT, scale: FRACTION, title: "CPU"),
          # Memory is read by the Ops Agent, so an instance without it has none.
          "memory" => Metric.new(type: "agent.googleapis.com/memory/percent_used", aligner: "ALIGN_MEAN", filter: 'metric.labels.state="used"',
                                 unit: PERCENT, title: "Memory used (Ops Agent)"),
          "network_in" => Metric.new(type: "compute.googleapis.com/instance/network/received_bytes_count", aligner: "ALIGN_RATE", reducer: "REDUCE_SUM",
                                     unit: BYTES_PER_SECOND, title: "Network in"),
          "network_out" => Metric.new(type: "compute.googleapis.com/instance/network/sent_bytes_count", aligner: "ALIGN_RATE", reducer: "REDUCE_SUM",
                                      unit: BYTES_PER_SECOND, title: "Network out")
        }.freeze
        BY_TYPE = { TYPE_RUN => RUN, TYPE_SQL => SQL, TYPE_MACHINE => MACHINE }.freeze
        DEFAULTS = { TYPE_RUN => %w[requests http_5xx cpu memory], TYPE_SQL => %w[cpu memory disk tcp_connections], TYPE_MACHINE => %w[cpu network_in network_out] }.freeze
        # What a baseline reads for each kind, once a day over a week.
        BASELINES = { TYPE_RUN => %w[requests http_5xx cpu memory latency_p95], TYPE_SQL => %w[cpu memory disk], TYPE_MACHINE => %w[cpu] }.freeze
        # Cloud Monitoring aligns no finer than a minute.
        MIN_ALIGNMENT = 60
        POINTS = 60

        # The metrics a kind of resource on the map has, each by the name every capability uses, which the pack takes as is.
        def self.names(kind) = BY_TYPE.fetch(TYPES_BY_KIND[kind], {}).keys.index_with(&:itself)
      end
    end
  end
end
