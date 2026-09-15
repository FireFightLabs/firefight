module FirefightAi
  class Engine < ::Rails::Engine
    isolate_namespace FirefightAi

    # Keeps model lookups off ruby_llm_models, a copy no gem upgrade refreshes. Runs after RubyLLM's hook sets it.
    initializer "firefight_ai.model_registry" do
      ActiveSupport.on_load(:active_record) { RubyLLM.config.model_registry_store = nil }
    end

    initializer "firefight_ai.configure_llm" do
      config.after_initialize do
        RubyLLM.configure do |c|
          FirefightAi.configuration.provider_settings.each do |setting, value|
            c.public_send("#{setting}=", value) if value.present?
          end
          c.request_timeout = FirefightAi.configuration.request_timeout
          # RubyLLM 2 defaults OpenAI to the Responses API, which OpenAI compatible bases may not serve.
          c.openai_protocol = :chat_completions
        end
      end
    end
  end
end
