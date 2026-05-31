module FirefightAi
  class Engine < ::Rails::Engine
    isolate_namespace FirefightAi

    initializer "firefight_ai.configure_llm" do
      config.after_initialize do
        RubyLLM.configure do |c|
          c.anthropic_api_key = FirefightAi.configuration.anthropic_api_key if FirefightAi.configuration.anthropic_api_key.present?
          c.request_timeout = FirefightAi.configuration.request_timeout
        end
      end
    end
  end
end
