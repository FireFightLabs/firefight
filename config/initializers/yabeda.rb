require "prometheus/client/support/puma"

Prometheus::Client.configuration.logger = Rails.logger
Prometheus::Client.configuration.pid_provider = Prometheus::Client::Support::Puma.method(:worker_pid_provider)

Yabeda::Rails.config.ignore_actions = %w[Rails::HealthController#show]

Yabeda::ActiveJob.install!

unless ENV["SOLID_QUEUE_IN_PUMA"]
  SolidQueue.on_start do
    Yabeda::Prometheus::Exporter.start_metrics_server!
  end
end
