module FirefightAi
  class Engine < ::Rails::Engine
    isolate_namespace FirefightAi

    initializer "firefight_ai.configure_llm" do
      config.after_initialize do
        RubyLLM.configure do |c|
          FirefightAi.configuration.provider_settings.each do |setting, value|
            c.public_send("#{setting}=", value) if value.present?
          end
          c.request_timeout = FirefightAi.configuration.request_timeout
        end
      end
    end
  end
end
