module AlertProviders
  # SigNoz's Webhook notification channel (signoz.io, Configure Webhook channel), which sends Alertmanager's alerts[]
  # shape. A password with no user name arrives as Authorization: Bearer, and both together as HTTP Basic auth.
  class Signoz < Alertmanager
    LABEL = "SigNoz".freeze
    SETUP_STEPS = [
      "In SigNoz, open Settings, then Notification Channels, and click New Channel. Choose the Webhook type.",
      "Paste this URL as the Webhook URL.",
      "Leave Username empty and paste the token as the Password.",
      "Leave Send resolved alerts on, so alerts resolve in Firefight when they resolve in SigNoz. Click Test, save, " \
      "and choose the channel in your alert rules."
    ].freeze

    # SigNoz's rule page, which newer versions send as generatorURL and every version as the ruleSource label.
    def self.link_for(alert)
      alert["generatorURL"].presence || alert.dig("labels", "ruleSource")
    end
  end
end
