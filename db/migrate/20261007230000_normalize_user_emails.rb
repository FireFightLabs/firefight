class NormalizeUserEmails < ActiveRecord::Migration[8.1]
  # Two rows that only differ in case or spaces are one person with two accounts, and which one they meant to keep is
  # theirs to say, so the migration stops and names them rather than picking.
  def up
    collisions = select_rows(<<~SQL)
      SELECT lower(btrim(email)), string_agg(id::text || ' ' || email, ', ' ORDER BY created_at)
      FROM users
      GROUP BY lower(btrim(email))
      HAVING count(*) > 1
    SQL

    if collisions.any?
      list = collisions.map { |normalized, rows| "#{normalized}: #{rows}" }.join("\n")
      raise ActiveRecord::MigrationError, "These users share an email once it is lowercased and trimmed. Merge or rename them, then run again.\n#{list}"
    end

    execute "UPDATE users SET email = lower(btrim(email)) WHERE email <> lower(btrim(email))"
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
  end

  def down
    remove_index :users, name: "index_users_on_lower_email"
  end
end
