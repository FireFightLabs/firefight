# Skip the OpenTelemetry SDK in test. Loading instrumentations adds ~3s to
# boot per process, and the BatchSpanProcessor blocks at shutdown trying to
# flush spans to localhost:4318. `Firefight::TRACER` still resolves below —
# without the SDK, OpenTelemetry's API returns a no-op tracer, so spans in
# app code become free no-ops instead of errors.
unless Rails.env.test?
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  OpenTelemetry::SDK.configure do |c|
    c.service_name = "firefight"
    c.service_version = ENV.fetch("KAMAL_VERSION", "dev")
    c.use_all
  end
end

# Shared tracer for all hand-rolled spans across the app. Use this instead of
# per-file TRACER constants so all custom spans show up under one source name
# in Tempo (easier to filter by `resource.scope.name = "firefight"`).
module Firefight
  TRACER = OpenTelemetry.tracer_provider.tracer("firefight")
end
