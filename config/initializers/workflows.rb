# Eager load workflow classes so they register in Base.registry
# This is needed in development where eager_load is false
Rails.application.config.to_prepare do
  Dir[Rails.root.join('app/workflows/**/*_workflow.rb')].each do |file|
    require_dependency file
  end
end
