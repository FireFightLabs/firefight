# opentelemetry-api is tiny and loads in every environment so `Firefight::TRACER`
# always resolves. The SDK only spins up when an OTLP endpoint is configured —
# in any environment. Without one, `OpenTelemetry.tracer_provider` returns the
# default ProxyTracerProvider, so spans become free no-ops with no boot cost, no
# instrumentation patching, and no BatchSpanProcessor flush at shutdown.
#
# Gating on the endpoint (not Rails.env) means tracing follows the config: set
# the endpoint in staging and it traces there too; leave it unset in prod and
# the SDK stays dormant instead of erroring trying to flush to localhost:4318.
require "opentelemetry"

if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  # Relevant env vars:
  #   OTEL_EXPORTER_OTLP_ENDPOINT  — where to send spans (Tempo/Honeycomb/etc).
  #                                  Presence of this var enables the SDK.
  #   OTEL_TRACES_SAMPLER          — e.g. "parentbased_traceidratio"
  #   OTEL_TRACES_SAMPLER_ARG      — e.g. "0.1" for 10% sampling. Default
  #                                  AlwaysOn generates one trace per request.
  #   OTEL_SERVICE_VERSION         — deployed commit SHA, if your platform exposes
  #                                  one. Falls back to "dev".
  OpenTelemetry::SDK.configure do |c|
    c.service_name = "firefight"
    c.service_version = ENV.fetch("OTEL_SERVICE_VERSION", "dev")
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
