# Why a memory stands where it does now quotes production and other memories, so it is encrypted like the memory. Reasons
# saved before are read as stored and written back encrypted, and one already encrypted is left as it is.
class EncryptMemoryStateReasons < ActiveRecord::Migration[8.1]
  class Memory < ActiveRecord::Base
    self.table_name = "chat_memories"
    encrypts :state_reason
  end

  def up
    select_rows("SELECT id, state_reason FROM chat_memories WHERE state_reason IS NOT NULL").each do |id, reason|
      next if reason.blank? || ActiveRecord::Encryption.encryptor.encrypted?(reason)

      store_reason(id, Memory.type_for_attribute(:state_reason).serialize(reason))
    end
  end

  def down
    select_rows("SELECT id, state_reason FROM chat_memories WHERE state_reason IS NOT NULL").each do |id, reason|
      next if reason.blank? || !ActiveRecord::Encryption.encryptor.encrypted?(reason)

      store_reason(id, Memory.type_for_attribute(:state_reason).deserialize(reason))
    end
  end

  private

  # Written as given, since update_all would put the value through the encrypted type a second time.
  def store_reason(id, value)
    exec_update("UPDATE chat_memories SET state_reason = $1 WHERE id = $2", "Write state reason", [ value, id ])
  end
end
