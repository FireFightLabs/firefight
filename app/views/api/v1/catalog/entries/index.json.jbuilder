json.entries @entries do |entry|
  json.partial! "api/v1/catalog/entries/entry", entry: entry
end

json.pagination do
  json.(@pagination, :page, :per_page, :total, :total_pages)
end
