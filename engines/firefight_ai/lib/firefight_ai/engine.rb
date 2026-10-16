module FirefightAi
  class Engine < ::Rails::Engine
    isolate_namespace FirefightAi

    initializer "firefight_ai.configure_llm" do
      config.after_initialize do
        adapter = FirefightAi::HttpAdapter.load!(FirefightAi.configuration.http_adapter)
        RubyLLM.configure do |c|
          FirefightAi.configuration.provider_settings.each do |setting, value|
            c.public_send("#{setting}=", value) if value.present?
          end
          c.request_timeout = FirefightAi.configuration.request_timeout
          c.faraday_adapter = adapter
        end
        FirefightAi::Tracing.span_tools!
        FirefightAi::Tracing.enable! if FirefightAi.configuration.trace_calls
      end
    end

    initializer "firefight_ai.keep_registry_current" do |app|
      app.executor.to_run { FirefightAi.keep_registry_current }
    end
  end
end
