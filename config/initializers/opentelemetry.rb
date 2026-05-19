require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "firefight"
  c.service_version = ENV.fetch("KAMAL_VERSION", "dev")
  c.use_all
end

# Shared tracer for all hand-rolled spans across the app. Use this instead of
# per-file TRACER constants so all custom spans show up under one source name
# in Tempo (easier to filter by `resource.scope.name = "firefight"`).
module Firefight
  TRACER = OpenTelemetry.tracer_provider.tracer("firefight")
end
