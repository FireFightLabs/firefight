# Each provider documentation source config/provider_docs.yml lists, as the daily refresh last found it: when it was
# read, the version or commit it was read at, its license, and what failed when it last could not be read.
class CreateProviderDocSources < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_doc_sources, id: :uuid do |t|
      t.string :key, null: false
      t.string :provider, null: false
      t.string :version
      t.text :license
      t.integer :page_count, null: false, default: 0
      t.datetime :fetched_at
      t.datetime :checked_at
      t.text :error
      t.timestamps
      t.index :key, unique: true
      t.index :provider
    end
  end
end
