require "test_helper"

module Ability
  class PrincipalTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
      @agent = SystemAgent.investigator
    end

    test "every workspace can grant the built in agent" do
      assert_includes Ability::Principal.all(@workspace), @agent
    end

    test "the listing shows only the grants made in the workspace being listed" do
      other = workspaces(:slack_workspace_two)
      Ability::Grant.create!(workspace: @workspace, principal: @agent, action: ability_actions(:alerts_read))
      Ability::Grant.create!(workspace: other, principal: @agent, action: ability_actions(:incidents_read))

      listed = Ability::Principal.all(@workspace).find { |principal| principal == @agent }

      assert_equal [ "alerts.read", Ability::Action::MAP_READ ], listed.ability_grants.map { |grant| grant.action.key }.sort,
                   "a global agent must not show another workspace's grants"
    end

    test "a built in agent is found by kind and id like any other principal" do
      assert_equal @agent,
                   Ability::Principal.find!(@workspace, Ability::Principal::KIND_SYSTEM_AGENT, @agent.id)
    end

    test "every kind the matrix renders is a kind the finder understands" do
      assert_includes Ability::Principal::KINDS, Ability::Principal::KIND_SYSTEM_AGENT
    end
  end
end
