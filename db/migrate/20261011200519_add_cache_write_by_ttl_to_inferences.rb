# A cache write lasting an hour costs twice what a five minute one does on Anthropic, so the ledger keeps the split it
# priced the call by.
class AddCacheWriteByTtlToInferences < ActiveRecord::Migration[8.1]
  def change
    add_column :inferences, :cache_write_tokens_by_ttl, :jsonb, default: {}, null: false
  end
end
