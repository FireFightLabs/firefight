# Errors only, and only where a deployment sets SENTRY_DSN, which is also what loaded the gems in config/application.rb.
Sentry.init { |config| ErrorReporting.configure(config) } if ErrorReporting.dsn
