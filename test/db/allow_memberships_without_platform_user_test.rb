require "test_helper"
require Rails.root.join("db/migrate/20261007230800_allow_memberships_without_platform_user")

class AllowMembershipsWithoutPlatformUserTest < ActiveSupport::TestCase
  setup do
    connection.remove_index :workspace_memberships, name: "index_workspace_memberships_on_workspace_and_user"
  end

  test "a person with two seats in one workspace stops the migration and is named" do
    seat = workspace_memberships(:alice_workspace_one)
    connection.execute(<<~SQL)
      INSERT INTO workspace_memberships (id, workspace_id, user_id, platform_user_id, role, joined_at, created_at, updated_at)
      VALUES (gen_random_uuid(), '#{seat.workspace_id}', '#{seat.user_id}', 'U_DOUBLE', 'member', now(), now(), now())
    SQL

    error = assert_raises(ActiveRecord::MigrationError) { migrate }

    assert_match seat.user_id, error.message
    assert_match seat.id, error.message
  end

  test "without duplicates the seat becomes unique per person" do
    migrate

    assert connection.index_exists?(:workspace_memberships, [ :workspace_id, :user_id ], unique: true)
    assert connection.columns(:workspace_memberships).find { |column| column.name == "platform_user_id" }.null
  end

  private

  def connection = ActiveRecord::Base.connection

  def migrate
    ActiveRecord::Migration.suppress_messages { AllowMembershipsWithoutPlatformUser.new.migrate(:up) }
  end
end
