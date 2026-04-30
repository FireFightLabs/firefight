# Map ENV-provided ActiveRecord encryption credentials into the Rails config.
#
# By default, Rails reads encryption keys from `Rails.application.credentials`,
# but in Kamal-deployed environments we inject them as env vars from a secret
# manager. Without this initializer, Rails would look in credentials, find
# nothing, and raise `ActiveRecord::Encryption::Errors::Configuration` the first
# time it tries to read or write an encrypted column.
#
# Required env vars in production: ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY,
# ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY,
# ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT.
#
# Falls back to credentials if env vars are absent (useful for local dev).
Rails.application.configure do
  primary_key         = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]         || Rails.application.credentials.dig(:active_record_encryption, :primary_key)
  deterministic_key   = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]   || Rails.application.credentials.dig(:active_record_encryption, :deterministic_key)
  key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt)

  config.active_record.encryption.primary_key         = primary_key         if primary_key.present?
  config.active_record.encryption.deterministic_key   = deterministic_key   if deterministic_key.present?
  config.active_record.encryption.key_derivation_salt = key_derivation_salt if key_derivation_salt.present?
end
