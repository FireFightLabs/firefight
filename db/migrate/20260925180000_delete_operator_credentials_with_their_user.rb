# Deleting a user deletes their operator credential in the database, so the user model does not need to know about the
# operator console.
class DeleteOperatorCredentialsWithTheirUser < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :operator_credentials, :users
    add_foreign_key :operator_credentials, :users, on_delete: :cascade
  end
end
