JsRoutes.setup do |config|
  config.file = Rails.root.join("app", "frontend", "lib", "routes.ts")

  config.exclude = [ /rails_/, /turbo_/, /action_/, /active_storage_/ ]

  config.camel_case = true
end
