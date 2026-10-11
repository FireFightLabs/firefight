module Integrations
  module Packs
    # A test login for one site, which Halon's browser signs in with (Integrations::SiteLogins). It offers no tools. It owns
    # the shape of the one secret it keeps, the password, which only the browser's run reads, through SiteLogins.
    class Website < NativePack
      PASSWORD = "password".freeze

      def self.credential_fields
        [ CredentialField.new(key: PASSWORD, label: "Password", secret: true, placeholder: "",
                              hint: "The test account's password. It is never shown again, and never reaches Halon.") ]
      end

      def self.credential_refusal(values, region: nil, fields: {})
        "Enter the test account's password." if values.to_h.stringify_keys[PASSWORD].to_s.empty?
      end

      # Kept as typed, since a password's spaces are part of it.
      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(PASSWORD, values.to_h.stringify_keys[PASSWORD].to_s)
      end

      def self.password_of(settings) = settings.credential(PASSWORD)
    end
  end
end
