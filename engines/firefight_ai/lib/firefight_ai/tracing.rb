module FirefightAi
  # Every model call, tool call and judgment as an OpenTelemetry span, exported wherever the deployment's SDK sends traces
  # (config/initializers/opentelemetry.rb, OTEL_EXPORTER_OTLP_ENDPOINT). RubyLLM::OpenTelemetry puts on a span only the
  # operation, the provider, the model, the output cap, token counts, the finish reason, a tool's name and call id, and an
  # error's class, never the messages, a tool's arguments or result, an error's message or a key.
  module Tracing
    NO_EXPORTER = "ai.tracing_without_exporter".freeze

    # Turned on by FIREFIGHT_AI_TRACING. Without an SDK to export through, spans would go nowhere, which is said once.
    def self.enable!
      unless exporting?
        Rails.logger.warn({ event: NO_EXPORTER }.to_json)
        return false
      end

      RubyLLM::OpenTelemetry.enable
      true
    end

    def self.disable! = RubyLLM::OpenTelemetry.disable

    def self.exporting?
      defined?(::OpenTelemetry::SDK::Trace::TracerProvider) && ::OpenTelemetry.tracer_provider.is_a?(::OpenTelemetry::SDK::Trace::TracerProvider)
    end
  end
end
