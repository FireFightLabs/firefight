require "test_helper"

module Ability
  class ResolverTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @key = api_keys(:full_access_key)
    end

    test "resolves direct grants with their scopes" do
      Ability::Grant.create!(workspace: @workspace, principal: @key, action: ability_actions(:alerts_read),
                             scope: { "environment" => [ "env-prod" ] })

      resolved = Ability::Resolver.resolve(@key)

      assert resolved.covers?("alerts.read", { "environment" => "env-prod" })
      assert_not resolved.covers?("alerts.read", { "environment" => "env-staging" })
      assert_not resolved.covers?("alerts.read", {})
      assert_not resolved.covers?("alerts.create")
    end

    test "an unscoped grant is unrestricted on every dimension" do
      Ability::Grant.create!(workspace: @workspace, principal: @key, action: ability_actions(:alerts_read))

      resolved = Ability::Resolver.resolve(@key)

      assert resolved.covers?("alerts.read")
      assert resolved.covers?("alerts.read", { "environment" => "env-prod" })
    end

    test "role grants contribute every role action; grant scope overrides the role default" do
      role = Ability::Role.create!(workspace: @workspace, name: "Observer", slug: "observer")
      Ability::RoleAction.create!(role: role, action: ability_actions(:alerts_read),
                                  default_scope: { "environment" => [ "env-dev" ] })
      Ability::RoleAction.create!(role: role, action: ability_actions(:runbooks_read))
      Ability::Grant.create!(workspace: @workspace, principal: @key, role: role,
                             scope: { "environment" => [ "env-prod" ] })

      resolved = Ability::Resolver.resolve(@key)

      assert resolved.covers?("alerts.read", { "environment" => "env-prod" })
      assert_not resolved.covers?("alerts.read", { "environment" => "env-dev" })
      assert resolved.covers?("runbooks.read", { "environment" => "env-prod" })
    end

    test "grant writes bust the cached resolution immediately" do
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(store)

      assert_not Ability::Resolver.resolve(@key).covers?("alerts.read")

      grant = Ability::Grant.create!(workspace: @workspace, principal: @key, action: ability_actions(:alerts_read))
      assert Ability::Resolver.resolve(@key).covers?("alerts.read")

      grant.destroy!
      assert_not Ability::Resolver.resolve(@key).covers?("alerts.read")
    end

    test "role membership changes bust every holder of the role" do
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(store)

      role = Ability::Role.create!(workspace: @workspace, name: "Observer", slug: "observer")
      Ability::Grant.create!(workspace: @workspace, principal: @key, role: role)
      assert_not Ability::Resolver.resolve(@key).covers?("alerts.read")

      Ability::RoleAction.create!(role: role, action: ability_actions(:alerts_read))
      assert Ability::Resolver.resolve(@key).covers?("alerts.read")
    end
  end
end
