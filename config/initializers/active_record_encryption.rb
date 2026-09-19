# Deployed environments inject the encryption keys as env vars from a secret manager. Rails reads
# config.active_record.encryption while loading Active Record, which happens before this file runs,
# so setting that config here is too late and the keys never arrive. Configuring encryption directly
# lands whenever this runs. Credentials remain the fallback, for anywhere the env vars are absent.
keys = {
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
}

ActiveRecord::Encryption.configure(**keys) if keys.values.all?(&:present?)
