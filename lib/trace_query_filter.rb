# Rack's instrumentation records a request's query as it came, and a sign-in or invitation link carries its token there.
# Each span's query is filtered as the request log's parameters are before anything exports it.
class TraceQueryFilter
  QUERY_KEYS = %w[url.query].freeze
  TARGET_KEYS = %w[http.target http.url url.full].freeze

  def on_start(span, _parent_context)
    QUERY_KEYS.each { |key| rewrite(span, key) { |value| filtered(value) } }
    TARGET_KEYS.each do |key|
      rewrite(span, key) do |value|
        address, query = value.split("?", 2)
        query ? "#{address}?#{filtered(query)}" : value
      end
    end
  end

  def on_finish(_span) = nil
  def force_flush(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS
  def shutdown(timeout: nil) = OpenTelemetry::SDK::Trace::Export::SUCCESS

  private

  def rewrite(span, key)
    value = span.attributes&.[](key)
    span.set_attribute(key, yield(value)) if value.is_a?(String)
  end

  def filtered(query)
    params = Rack::Utils.parse_query(query)
    Rack::Utils.build_query(ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params))
  end
end
