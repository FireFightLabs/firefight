JsRoutes.setup do |config|
  # Output to frontend directory
  config.file = Rails.root.join('app', 'frontend', 'lib', 'routes.ts')

  # Exclude Rails internal routes
  config.exclude = [/rails_/, /turbo_/, /action_/, /active_storage_/]

  # Use camelCase for JavaScript routes
  config.camel_case = true
end
