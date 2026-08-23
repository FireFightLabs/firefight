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

    test "an expired grant stops resolving" do
      grant = Grant.create!(workspace: @workspace, principal: @key,
                            action: Action.system!("runbooks.read"), expires_at: 1.hour.from_now)
      assert Resolver.resolve(@key).covers?("runbooks.read")

      travel 2.hours do
        Resolver.bust!(principal_type: @key.class.polymorphic_name, principal_id: @key.id)
        assert_not Resolver.resolve(@key).covers?("runbooks.read")
      end
      assert grant.reload.persisted?, "the row stays so the screen can show it lapsed"
    end

    # The cache lives an hour. Without capping it against the soonest expiry a
    # grant lapsing in ten minutes would keep working for the other fifty.
    test "the cache never outlives the next expiry" do
      Grant.create!(workspace: @workspace, principal: @key,
                    action: Action.system!("runbooks.read"), expires_at: 10.minutes.from_now)

      assert_in_delta 10.minutes, Resolver.cache_ttl_for(@key), 5.seconds
    end

    test "a grant with no expiry keeps the full cache window" do
      Grant.create!(workspace: @workspace, principal: @key, action: Action.system!("runbooks.create"))

      assert_equal Resolver::CACHE_TTL, Resolver.cache_ttl_for(@key)
    end

    test "an expiry further out than the cache window does not extend it" do
      Grant.create!(workspace: @workspace, principal: @key,
                    action: Action.system!("runbooks.update"), expires_at: 5.days.from_now)

      assert_equal Resolver::CACHE_TTL, Resolver.cache_ttl_for(@key)
    end

    # What the expiry is for, the gateway itself refuses once it lapses.
    test "the gateway denies a call once the grant expires" do
      Grant.create!(workspace: @workspace, principal: @key,
                    action: Action.system!("runbooks.create"), expires_at: 1.hour.from_now)

      assert_nothing_raised do
        AbilityGateway.authorize!(principal: @key, action_key: "runbooks.create", workspace: @workspace)
      end

      travel 2.hours do
        Resolver.bust!(principal_type: @key.class.polymorphic_name, principal_id: @key.id)
        assert_raises(AbilityGateway::Denied) do
          AbilityGateway.authorize!(principal: @key, action_key: "runbooks.create", workspace: @workspace)
        end
      end
    end
  end
end
