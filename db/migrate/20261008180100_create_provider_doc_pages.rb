# One page of a provider's documentation, with the address it was read from so Halon can cite it. A page is named by its
# path within its provider, which is what a skill lists under references.
class CreateProviderDocPages < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_doc_pages, id: :uuid do |t|
      t.references :provider_doc_source, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :path, null: false
      t.string :url, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :content_digest, null: false
      t.string :revision
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index [ :provider, :path ], unique: true
    end
  end
end
