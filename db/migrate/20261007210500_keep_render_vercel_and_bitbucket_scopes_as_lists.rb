# A Render, Vercel or Bitbucket connection now reads one, several or every workspace or team its credential can read,
# so the field naming it holds a list. Each environment row's one workspace or team becomes a list of it, and reads
# exactly as before. A Vercel row that named no team keeps naming none, which reads the token's own account.
class KeepRenderVercelAndBitbucketScopesAsLists < ActiveRecord::Migration[8.1]
  FIELDS = { "render" => "workspace", "vercel" => "team", "bitbucket" => "workspace" }.freeze

  def up
    each_row do |row, key|
      value = row.fields[key]
      next unless value.is_a?(String)

      store(row, key, value.strip.presence && [ value.strip ])
    end
  end

  def down
    each_row do |row, key|
      values = row.fields[key]
      next unless values.is_a?(Array)

      store(row, key, values.first)
    end
  end

  private

  def each_row
    IntegrationEnvironment.joins(:integration).where(integrations: { provider: FIELDS.keys }).includes(:integration).find_each do |row|
      yield row, FIELDS.fetch(row.integration.provider)
    end
  end

  def store(row, key, value)
    row.update_columns(base_config: row.base_config.to_h.merge(IntegrationEnvironment::FIELDS_KEY => row.fields.merge(key => value).compact))
  end
end
