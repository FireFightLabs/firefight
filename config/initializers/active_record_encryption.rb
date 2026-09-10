# Deployed environments inject the encryption keys as env vars from a secret manager. Rails only
# looks in credentials, and would raise on the first encrypted column read. Credentials remain the fallback.
Rails.application.configure do
  primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]         || Rails.application.credentials.dig(:active_record_encryption, :primary_key)
  deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]   || Rails.application.credentials.dig(:active_record_encryption, :deterministic_key)
  key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt)

  config.active_record.encryption.primary_key         = primary_key         if primary_key.present?
  config.active_record.encryption.deterministic_key   = deterministic_key   if deterministic_key.present?
  config.active_record.encryption.key_derivation_salt = key_derivation_salt if key_derivation_salt.present?
end
