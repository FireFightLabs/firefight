# The SDK only starts when an OTLP endpoint is set, in any environment. Without one the
# tracer is a no-op proxy, so spans cost nothing and nothing flushes at shutdown.
require "opentelemetry"

if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/instrumentation/all"

  # OTEL_TRACES_SAMPLER and OTEL_TRACES_SAMPLER_ARG control sampling, the default traces every request.
  OpenTelemetry::SDK.configure do |c|
    c.service_name = "firefight"
    c.service_version = ENV.fetch("OTEL_SERVICE_VERSION", "dev")
    c.resource = OpenTelemetry::SDK::Resources::Resource.create(
      "deployment.environment" => ENV.fetch("DEPLOYMENT_ENVIRONMENT", Rails.env)
    )
    c.use_all
  end
end

# Put first after the tracer put itself first above, so neither a span nor a request log records a secret in a path.
require Rails.root.join("app/middleware/path_secret")
Rails.application.config.middleware.insert_before 0, PathSecret

# One tracer for every hand-rolled span, so they share a source name in Tempo.
module Firefight
  TRACER = OpenTelemetry.tracer_provider.tracer("firefight")
end
