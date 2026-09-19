# Configured directly because Rails reads the encryption config before initializers run, so setting it there is too late.
keys = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

ActiveRecord::Encryption.configure(**keys) if keys.values.all?(&:present?)
