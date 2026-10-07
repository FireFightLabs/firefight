require "test_helper"
require Rails.root.join("db/migrate/20261007230000_normalize_user_emails")

class NormalizeUserEmailsTest < ActiveSupport::TestCase
  setup do
    connection.remove_index :users, name: "index_users_on_lower_email"
  end

  test "emails are lowercased and trimmed, and the case-blind unique index is added" do
    user = User.create!(email: "mixed@example.com", name: "Mixed")
    connection.execute("UPDATE users SET email = '  Mixed@Example.COM ' WHERE id = '#{user.id}'")

    migrate

    assert_equal "mixed@example.com", connection.select_value("SELECT email FROM users WHERE id = '#{user.id}'")
    assert connection.index_exists?(:users, nil, name: "index_users_on_lower_email")
  end

  test "two people who share an email once normalized stop the migration and are named" do
    first = User.create!(email: "twin@example.com", name: "First")
    second = User.create!(email: "twin-two@example.com", name: "Second")
    connection.execute("UPDATE users SET email = 'Twin@Example.com' WHERE id = '#{second.id}'")

    error = assert_raises(ActiveRecord::MigrationError) { migrate }

    assert_match "twin@example.com", error.message
    assert_match first.id, error.message
    assert_match second.id, error.message
    assert_equal "Twin@Example.com", connection.select_value("SELECT email FROM users WHERE id = '#{second.id}'")
  end

  private

  def connection = ActiveRecord::Base.connection

  def migrate
    ActiveRecord::Migration.suppress_messages { NormalizeUserEmails.new.migrate(:up) }
  end
end
