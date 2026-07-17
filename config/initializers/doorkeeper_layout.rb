# The consent screen is a standalone page, not part of the Inertia app shell.
Rails.application.config.to_prepare do
  Doorkeeper::AuthorizationsController.layout "oauth"
end
