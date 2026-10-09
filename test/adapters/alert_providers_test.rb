require "test_helper"

class AlertProvidersTest < ActiveSupport::TestCase
  test "every provider says how a source is pointed at its URL, naming the header its token travels in" do
    instructions = AlertProviders.setup_instructions

    assert_equal AlertSource::PROVIDERS.sort, instructions.keys.sort
    assert_includes instructions[AlertSource::PROVIDER_PAGERDUTY], "incident.triggered, incident.reopened and incident.resolved"
    assert_includes instructions[AlertSource::PROVIDER_NORTHFLANK], AlertProviders::Northflank::TOKEN_HEADER
  end
end
