module FirefightAi
  # Every model call, tool call and judgment as an OpenTelemetry span, exported wherever the deployment's SDK sends traces
  # (config/initializers/opentelemetry.rb, OTEL_EXPORTER_OTLP_ENDPOINT). RubyLLM::OpenTelemetry puts on a span only the
  # operation, the provider, the model, the output cap, token counts, the finish reason, a tool's name and call id, and an
  # error's class, never the messages, a tool's arguments or result, an error's message or a key.
  #
  # Tool calls are spanned whether or not the rest is (ToolSpans), so a reply's trace shows where its tools spent their
  # time, and a thread that runs tools carries the trace of the work that started it.
  module Tracing
    NO_EXPORTER = "ai.tracing_without_exporter".freeze

    # Turned on by FIREFIGHT_AI_TRACING. Without an SDK to export through, spans would go nowhere, which is said once.
    def self.enable!
      unless exporting?
        Rails.logger.warn({ event: NO_EXPORTER }.to_json)
        return false
      end

      RubyLLM::OpenTelemetry.enable
      @calls_traced = true
    end

    def self.disable!
      @calls_traced = false
      RubyLLM::OpenTelemetry.disable
    end

    # RubyLLM::OpenTelemetry spans tool calls itself while it is on.
    def self.calls_traced? = @calls_traced == true

    def self.exporting?
      defined?(::OpenTelemetry::SDK::Trace::TracerProvider) && ::OpenTelemetry.tracer_provider.is_a?(::OpenTelemetry::SDK::Trace::TracerProvider)
    end

    # Always on, and costs nothing while no SDK exports.
    def self.span_tools! = RubyLLM::Support::Instrumentation.subscribe(@tool_spans ||= ToolSpans.new)

    # The trace a thread started by the loop carries over, so its spans nest under the work that started it.
    def self.context = ::OpenTelemetry::Context.current

    def self.within(context, &) = ::OpenTelemetry::Context.with_current(context, &)

    # Each tool call as a span named for the tool, with the same attributes RubyLLM::OpenTelemetry gives it. RubyLLM hands
    # the trace of the step to each thread it runs a tool on through capture_context and with_context.
    class ToolSpans
      EVENT = "tool_call.ruby_llm".freeze
      OPERATION = "execute_tool".freeze

      def instrument(name, payload)
        return yield unless name == EVENT && !Tracing.calls_traced?

        attributes = { "gen_ai.operation.name" => OPERATION, "gen_ai.tool.name" => payload[:tool_name].to_s,
                       "gen_ai.tool.call.id" => payload[:tool_call_id].to_s }
        # in_span marks a span whose block raised as an error, naming only the class, and so does error.type.
        tracer.in_span("#{OPERATION} #{payload[:tool_name]}", attributes: attributes, record_exception: false) do |span|
          yield
        rescue StandardError => error
          span.set_attribute("error.type", error.class.name)
          raise
        end
      end

      def capture_context = Tracing.context

      def with_context(context, &) = Tracing.within(context, &)

      private

      def tracer = ::OpenTelemetry.tracer_provider.tracer("firefight_ai", FirefightAi::VERSION)
    end
  end
end
