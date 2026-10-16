# Outbound webhook signing secrets are encrypted at rest like every other credential Firefight keeps. Secrets saved
# before are read as stored and written back encrypted, and a secret already encrypted is left as it is.
class EncryptOutboundWebhookSigningSecrets < ActiveRecord::Migration[8.1]
  class Webhook < ActiveRecord::Base
    self.table_name = "webhooks"
    encrypts :signing_secret
  end

  def up
    select_rows("SELECT id, signing_secret FROM webhooks").each do |id, secret|
      next if secret.blank? || ActiveRecord::Encryption.encryptor.encrypted?(secret)

      Webhook.where(id: id).update_all(signing_secret: Webhook.type_for_attribute(:signing_secret).serialize(secret))
    end
  end

  def down
    select_rows("SELECT id, signing_secret FROM webhooks").each do |id, secret|
      next if secret.blank? || !ActiveRecord::Encryption.encryptor.encrypted?(secret)

      Webhook.where(id: id).update_all(signing_secret: Webhook.type_for_attribute(:signing_secret).deserialize(secret))
    end
  end
end
