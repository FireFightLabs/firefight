# opentelemetry-api is tiny and loads in every environment so `Firefight::TRACER`
# always resolves. Outside production we stop here — `OpenTelemetry.tracer_provider`
# returns the default ProxyTracerProvider, so spans become free no-ops with no boot
# cost, no instrumentation patching, and no BatchSpanProcessor flush at shutdown.
require "opentelemetry"

if Rails.env.production?
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
