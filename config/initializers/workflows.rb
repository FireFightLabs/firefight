# Eager load workflow classes so they register in Base.registry
# This is only needed in development where eager_load is false
# In staging/production, eager_load is true and this happens automatically
Rails.application.config.to_prepare do
  if Rails.env.development? && !Rails.configuration.eager_load
    Dir[Rails.root.join("app/workflows/**/*_workflow.rb")].each do |file|
      require_dependency file
    end
  end
end
