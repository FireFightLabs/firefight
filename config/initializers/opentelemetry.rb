require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = "firefight"
  c.service_version = ENV.fetch("KAMAL_VERSION", "dev")
  c.use_all
end
