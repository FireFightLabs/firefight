module Integrations
  # Reads an app installation again after the provider said something about it changed, such as what it shares or what
  # it was granted (Integrations::Installations).
  class InstallationCheckJob < ApplicationJob
    queue_as :default

    def perform(environment_row)
      Installations.check!(environment_row)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "installations.check_failed", integration_environment_id: environment_row.id, error: error.message.truncate(200) }.to_json)
    end
  end
end
