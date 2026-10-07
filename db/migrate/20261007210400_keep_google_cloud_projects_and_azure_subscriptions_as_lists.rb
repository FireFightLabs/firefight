# A Google Cloud or Azure connection now reads one, several or every project or subscription its credentials can read,
# so the field naming it holds a list. Each environment row's one value becomes a list of it, and reads exactly as before.
class KeepGoogleCloudProjectsAndAzureSubscriptionsAsLists < ActiveRecord::Migration[8.1]
  FIELDS = { "google_cloud" => "project", "azure" => "subscription_id" }.freeze

  def up
    each_row do |row, key|
      value = row.fields[key]
      store(row, key, value.strip.presence && [ value.strip ]) if value.is_a?(String)
    end
  end

  def down
    each_row do |row, key|
      value = row.fields[key]
      store(row, key, value.first) if value.is_a?(Array)
    end
  end

  private

  def each_row
    FIELDS.each do |provider, key|
      IntegrationEnvironment.joins(:integration).where(integrations: { provider: provider }).find_each { |row| yield row, key }
    end
  end

  def store(row, key, value)
    row.update_columns(base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.merge(key => value).compact))
  end
end
