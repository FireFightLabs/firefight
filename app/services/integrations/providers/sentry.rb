module Integrations
  module Providers
    Sentry = Provider.new(key: "sentry", adapter: "Integrations::Capabilities::Sentry", error_reader: "Integrations::ErrorReaders::Sentry",
                          read_guard: "Integrations::ReadGuards::Sentry")
  end
end
