# opentelemetry-api is tiny and loads in every environment so `Firefight::TRACER`
# always resolves. Outside production we stop here — `OpenTelemetry.tracer_provider`
# returns the default ProxyTracerProvider, so spans become free no-ops with no boot
# cost, no instrumentation patching, and no BatchSpanProcessor flush at shutdown.
require "opentelemetry"

if Rails.env.production?
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  # Required env vars in production (set via Kamal secrets / deploy.yml):
  #   OTEL_EXPORTER_OTLP_ENDPOINT  — where to send spans (Tempo/Honeycomb/etc).
  #                                  Without this the exporter silently drops to
  #                                  localhost:4318 and times out at shutdown.
  #   OTEL_TRACES_SAMPLER          — e.g. "parentbased_traceidratio"
  #   OTEL_TRACES_SAMPLER_ARG      — e.g. "0.1" for 10% sampling. Default
  #                                  AlwaysOn generates one trace per request.
  #   KAMAL_VERSION                — deployed commit SHA. Kamal does NOT inject
  #                                  this automatically; wire it via deploy.yml.
  OpenTelemetry::SDK.configure do |c|
    c.service_name = "firefight"
    c.service_version = ENV.fetch("KAMAL_VERSION", "dev")
    c.resource = OpenTelemetry::SDK::Resources::Resource.create(
      "deployment.environment" => ENV.fetch("DEPLOYMENT_ENVIRONMENT", Rails.env)
    )
    c.use_all
  end
end

# Shared tracer for all hand-rolled spans across the app. Use this instead of
# per-file TRACER constants so all custom spans show up under one source name
# in Tempo (easier to filter by `resource.scope.name = "firefight"`).
module Firefight
  TRACER = OpenTelemetry.tracer_provider.tracer("firefight")
end
