# Devin's ACU limit per change is a connect field named max_acus, with Devin's default when it is left empty. A limit a
# Devin environment row kept in its credentials or under the field's earlier name moves across, and the credentials keep
# only the key.
class MoveDevinAcuLimitToMaxAcus < ActiveRecord::Migration[8.1]
  PROVIDER = "devin".freeze
  OLD_KEY = "acu_limit".freeze
  NEW_KEY = "max_acus".freeze

  def up
    rows.find_each do |row|
      credentials = row.credentials_hash
      limit = credentials.delete(OLD_KEY).to_s.strip.presence || row.fields[OLD_KEY].to_s.strip.presence
      fields = row.fields.except(OLD_KEY)
      fields = fields.merge(NEW_KEY => limit) if limit
      row.update!(credentials: credentials.to_json, base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => fields))
    end
  end

  def down
    rows.find_each do |row|
      limit = row.fields[NEW_KEY]
      next if limit.blank?

      row.update!(base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.except(NEW_KEY).merge(OLD_KEY => limit)))
    end
  end

  private

  def rows = IntegrationEnvironment.joins(:integration).where(integrations: { provider: PROVIDER })
end
