require "test_helper"
require "opentelemetry/sdk"

# Model calls as OpenTelemetry spans carry what an operator needs to see cost and latency, and never what was said, what
# a tool was asked or answered, an error's words or a key.
class FirefightAi::TracingTest < ActiveSupport::TestCase
  include FakeProviderHelper

  KEY = "sk-ant-api03-tracing-key-never-exported".freeze
  ASKED = "Why is checkout failing for the customer with card 4242?".freeze
  ANSWERED = "Their payment token expired at 14:02.".freeze
  TOOL_ASKED = "orders-db-primary".freeze
  TOOL_ANSWERED = "connections: 512 of 512 in use".freeze

  class ReadStatus < RubyLLM::Tool
    description "Reads a resource's status"

    def name = "read_status"

    def parameters_schema = { "type" => "object", "properties" => { "resource" => { "type" => "string" } } }

    def call(tool_call: nil, **) = TOOL_ANSWERED
  end

  setup do
    FakeProviderHelper::Adapter.reset!
    @before = OpenTelemetry.tracer_provider
    @exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    @provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    @provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@exporter))
    OpenTelemetry.tracer_provider = @provider
  end

  # Shut down, so a tracer that reached it through the global proxy records nothing after this test.
  teardown do
    FirefightAi::Tracing.disable!
    @provider.shutdown
    OpenTelemetry.tracer_provider = @before
  end

  test "a model call and the tool it ran are spans with the model, the provider and token counts, and nothing that was said" do
    assert FirefightAi::Tracing.enable!
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_1", name: "read_status", input: { resource: TOOL_ASKED } } ],
                  usage: { input_tokens: 120, output_tokens: 15 } })
    answer_with({ id: "msg_2", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "end_turn",
                  content: [ { type: "text", text: ANSWERED } ], usage: { input_tokens: 160, output_tokens: 12, cache_read_input_tokens: 100 } })

    chat.with_tools(ReadStatus.new).ask(ASKED)

    spans = @exporter.finished_spans
    assert_equal [ "chat claude-haiku-4-5", "execute_tool read_status" ], spans.map(&:name).uniq.sort
    model_call = spans.find { |span| span.name.start_with?("chat") }
    assert_equal [ "anthropic", "claude-haiku-4-5" ], model_call.attributes.values_at("gen_ai.provider.name", "gen_ai.request.model")
    assert(spans.any? { |span| span.attributes["gen_ai.usage.output_tokens"].to_i.positive? })
    assert_nothing_said(spans)
  end

  test "a refused call says only the error's class, never its words" do
    FirefightAi::Tracing.enable!
    answer_with({ type: "error", error: { type: "invalid_request_error", message: "Bad input near: #{ASKED}" } }, status: 400)

    assert_raises(RubyLLM::BadRequestError) { chat.ask(ASKED) }

    span = @exporter.finished_spans.sole
    assert_equal "RubyLLM::BadRequestError", span.attributes["error.type"]
    assert_nothing_said([ span ])
  end

  test "without an SDK exporting traces, calls are not traced and the log says so" do
    OpenTelemetry.tracer_provider = OpenTelemetry::Trace::TracerProvider.new
    logged = []
    Rails.logger.stubs(:warn).with { |line| logged << line }

    assert_not FirefightAi::Tracing.enable!
    assert_equal [ FirefightAi::Tracing::NO_EXPORTER ], logged.map { |line| JSON.parse(line)["event"] }
  end

  private

  def chat = fake_provider_context(anthropic_api_key: KEY).chat(model: "claude-haiku-4-5", provider: :anthropic, assume_model_exists: true)

  def assert_nothing_said(spans)
    exported = spans.flat_map { |span| [ span.name, *span.attributes.to_a.flatten, *Array(span.events).flat_map { |event| [ event.name, *event.attributes.to_a.flatten ] } ] }.join("\n")
    [ KEY, ASKED, ANSWERED, TOOL_ASKED, TOOL_ANSWERED, "4242" ].each { |said| assert_not_includes exported, said }
  end
end
