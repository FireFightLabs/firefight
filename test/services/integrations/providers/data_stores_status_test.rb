require "test_helper"

module Integrations
  module Providers
    class DataStoresStatusTest < ActiveSupport::TestCase
      # Every state a reader can report for these providers reads as a health Firefight knows, so nothing on the map shows
      # unknown health in its normal state.
      STATES = {
        "clickhouse" => %w[starting stopping terminating softdeleting awaking partially_running provisioning running stopped terminated
                           softdeleted degraded failed idle],
        "turso" => [ "active", "reads blocked", "writes blocked", "reads and writes blocked" ],
        "upstash" => %w[active suspended inactive]
      }.freeze

      test "every state ClickHouse, Turso and Upstash report maps onto a health the map knows" do
        STATES.each do |key, states|
          definition = Provider.for(key)
          states.each do |state|
            health = ResourceMap::Resource.new(status: definition.status_of(state)).health
            assert_not_equal ResourceMap::Resource::HEALTH_UNKNOWN, health, "#{key} #{state} reads as unknown health"
          end
        end
        assert_equal "unavailable", Provider.for("turso").status_of("writes blocked")
        assert_equal "sleeping", Provider.for("clickhouse").status_of("idle")
      end
    end
  end
end
