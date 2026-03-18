module SolidWorkflow
  class Engine < ::Rails::Engine
    isolate_namespace SolidWorkflow

    initializer "solid_workflow.load_base" do
      require "solid_workflow/idempotent_steps"
      require "solid_workflow/base"
    end

    initializer "solid_workflow.eager_load_workflows" do
      config.to_prepare do
        if Rails.env.development? && !Rails.configuration.eager_load
          Dir[Rails.root.join("app/workflows/**/*_workflow.rb")].each do |file|
            require_dependency file
          end
        end
      end
    end
  end
end
