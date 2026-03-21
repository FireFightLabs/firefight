module FirefightAi
  class Engine < ::Rails::Engine
    isolate_namespace FirefightAi

    initializer "firefight_ai.configure_llm" do
      config.after_initialize do
        if FirefightAi.configuration.anthropic_api_key.present?
          RubyLLM.configure do |c|
            c.anthropic_api_key = FirefightAi.configuration.anthropic_api_key
          end
        end
      end
    end
  end
end
