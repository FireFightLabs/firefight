# Which box saves a provider's copy of one sandbox image version, so boxes starting at once never all save it.
class CreateSandboxImageCopies < ActiveRecord::Migration[8.1]
  def change
    create_table :sandbox_image_copies, id: :uuid do |t|
      t.string :provider, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "unclaimed"
      t.string :claimed_by
      t.datetime :claimed_at
      t.timestamps
      t.index [ :provider, :name ], unique: true
    end
  end
end
