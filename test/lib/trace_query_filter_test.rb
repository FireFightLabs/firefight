require "test_helper"
require "opentelemetry/sdk"

class TraceQueryFilterTest < ActiveSupport::TestCase
  setup do
    @exporter = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    @provider = OpenTelemetry::SDK::Trace::TracerProvider.new
    @provider.add_span_processor(TraceQueryFilter.new)
    @provider.add_span_processor(OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(@exporter))
  end

  test "a sign-in or invitation token in a request's query never reaches a trace, while the rest of the query does" do
    attributes = {
      "url.query" => "token=sign-in-secret&step=2",
      "http.target" => "/auth/invitation?token=invite-secret&step=2",
      "http.url" => "https://firefight.example/auth/email/confirm?token=link-secret"
    }

    @provider.tracer("test").start_span("GET", attributes: attributes).finish

    recorded = @exporter.finished_spans.first.attributes
    assert_equal "token=%5BFILTERED%5D&step=2", recorded["url.query"]
    assert_equal "/auth/invitation?token=%5BFILTERED%5D&step=2", recorded["http.target"]
    assert_equal "https://firefight.example/auth/email/confirm?token=%5BFILTERED%5D", recorded["http.url"]
    assert_no_match(/secret/, recorded.values.join)
  end

  test "a span without a query is left as it is" do
    @provider.tracer("test").start_span("GET", attributes: { "http.target" => "/app/incidents" }).finish

    assert_equal "/app/incidents", @exporter.finished_spans.first.attributes["http.target"]
  end
end
