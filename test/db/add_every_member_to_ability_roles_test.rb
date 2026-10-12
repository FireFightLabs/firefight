require "test_helper"
require Rails.root.join("db/migrate/20261012141000_add_every_member_to_ability_roles")
require Rails.root.join("db/migrate/20261012141500_sync_github_operations_tools")

class AddEveryMemberToAbilityRolesTest < ActiveSupport::TestCase
  teardown { Ability::Role.reset_column_information }

  test "the column is added before the GitHub sync, which reads it" do
    versions = migrations.to_h { |migration| [ migration.name, migration.version ] }

    assert_operator versions.fetch("AddEveryMemberToAbilityRoles"), :<, versions.fetch("SyncGithubOperationsTools")
  end

  test "a database from before the column migrates up through the GitHub sync" do
    github = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    migrate(AddEveryMemberToAbilityRoles, :down)
    assert_not column_exists?

    pending = migrations.select { |migration| migration.version > 20261012140000 && migration.version <= 20261012141500 }
    pending.sort_by(&:version).each { |migration| migrate(migration.name.constantize, :up) }

    assert column_exists?
    assert github.tools.exists?(name: "pending_deployments")
    assert Ability::Role.where(integration: github, pack: Ability::Role::PACK_READ).all?(&:every_member?)
  end

  test "running again on a database that already has the column keeps it and its read packs held by every member" do
    github = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    Ability::Role.keep_in_step!(github)
    Ability::Role.where(integration: github, pack: Ability::Role::PACK_READ).update_all(every_member: false)

    migrate(AddEveryMemberToAbilityRoles, :up)

    assert column_exists?
    assert Ability::Role.where(integration: github, pack: Ability::Role::PACK_READ).all?(&:every_member?)
  end

  private

  def migrations
    ActiveRecord::MigrationContext.new(Rails.root.join("db/migrate")).migrations
  end

  def column_exists?
    ActiveRecord::Base.lease_connection.column_exists?(:ability_roles, :every_member)
  end

  def migrate(migration, direction)
    ActiveRecord::Migration.suppress_messages { migration.new.migrate(direction) }
    Ability::Role.reset_column_information
  end
end
