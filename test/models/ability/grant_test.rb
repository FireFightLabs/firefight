require "test_helper"

module Ability
  class GrantTest < ActiveSupport::TestCase
    fixtures :workspaces, :users, :workspace_memberships, :api_keys, :ability_actions, :ability_grants

    setup do
      @workspace = workspaces(:slack_workspace_one)
      @key = api_keys(:read_only_key)
    end

    test "a grant targets exactly one of role or action" do
      role = Ability::Role.create!(workspace: @workspace, name: "Responder", slug: "responder")
      action = ability_actions(:incidents_read)

      assert_not Ability::Grant.new(workspace: @workspace, principal: @key).valid?
      assert_not Ability::Grant.new(workspace: @workspace, principal: @key, role: role, action: action).valid?
      assert Ability::Grant.new(workspace: @workspace, principal: @key, role: role).valid?
    end

    test "scope must use known dimensions and non-empty id arrays" do
      grant = Ability::Grant.new(workspace: @workspace, principal: @key, action: ability_actions(:alerts_read))

      grant.scope = { "environment" => [] }
      assert_not grant.valid?

      grant.scope = { "region" => [ "us" ] }
      assert_not grant.valid?

      grant.scope = { "environment" => [ "abc-123" ] }
      assert grant.valid?
    end

    test "sync_direct! reconciles managed grants and never touches unmanaged ones" do
      tool_action = Ability::Action.create!(workspace: @workspace, kind: Ability::Action::KIND_TOOL,
                                            key: "datadog.logs.query", risk_level: Ability::Action::RISK_READ)
      tool_grant = Ability::Grant.create!(workspace: @workspace, principal: @key, action: tool_action)

      Ability::Grant.sync_direct!(
        principal: @key, workspace: @workspace,
        desired_keys: [ "incidents.read", "alerts.read" ],
        managed_keys: ApiKey.managed_ability_keys
      )

      keys = Ability::Grant.where(principal: @key).joins(:action).pluck(Ability::Action.arel_table[:key])
      assert_equal [ "alerts.read", "datadog.logs.query", "incidents.read" ], keys.sort
      assert Ability::Grant.exists?(tool_grant.id)
    end

    test "an expiry in the past is refused" do
      grant = Grant.new(workspace: @workspace, principal: @key,
                        action: Action.system!("runbooks.read"), expires_at: 1.hour.ago)

      assert_not grant.valid?
      assert_includes grant.errors[:expires_at], "must be in the future"
    end

    test "the live scope keeps unexpiring and future grants, and drops lapsed ones" do
      forever = Grant.create!(workspace: @workspace, principal: @key, action: Action.system!("runbooks.read"))
      later = Grant.create!(workspace: @workspace, principal: @key,
                            action: Action.system!("runbooks.create"), expires_at: 1.day.from_now)

      live = Grant.where(principal: @key).live.pluck(:id)
      assert_includes live, forever.id
      assert_includes live, later.id

      travel 2.days do
        lapsed = Grant.where(principal: @key).live.pluck(:id)
        assert_not_includes lapsed, later.id
        assert_includes lapsed, forever.id
      end
    end

    # A service key's matrix is its write interface, so a switch left on must
    # never point at a grant that quietly lapsed.
    test "syncing a service key's permissions clears an expiry" do
      grant = Grant.create!(workspace: @workspace, principal: @key,
                            action: Action.system!("runbooks.read"), expires_at: 1.day.from_now)

      Grant.sync_direct!(principal: @key, workspace: @workspace,
                         desired_keys: [ "runbooks.read" ], managed_keys: [ "runbooks.read" ])

      assert_nil grant.reload.expires_at
    end
  end
end
