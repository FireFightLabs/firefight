require "test_helper"

class AlertProvidersTest < ActiveSupport::TestCase
  test "every provider has an adapter, a label and steps saying where its URL and token go" do
    catalog = AlertProviders.catalog

    assert_equal AlertSource::PROVIDERS.sort, catalog.pluck(:provider).sort
    assert_equal AlertSource::PROVIDER_GENERIC, catalog.first[:provider]
    catalog.each do |entry|
      assert entry[:label].present?, entry[:provider]
      assert entry[:steps].any? { |step| step.include?("this URL") }, "#{entry[:provider]} never says where the URL goes"
      secret_step = entry[:secretFromProvider] ? "paste it below" : "token"
      assert entry[:steps].any? { |step| step.include?(secret_step) }, "#{entry[:provider]} never says where the secret goes"
    end
  end

  test "a provider names what its tool calls things, and only the generic webhook maps fields" do
    pagerduty = AlertProviders.catalog.find { |entry| entry[:provider] == AlertSource::PROVIDER_PAGERDUTY }

    assert_includes pagerduty[:steps].join(" "), "incident.triggered, incident.reopened and incident.resolved"
    assert_equal [ AlertSource::PROVIDER_GENERIC ], AlertProviders.catalog.select { |entry| entry[:fieldMapping] }.pluck(:provider)
    assert_equal [ AlertSource::PROVIDER_SENTRY ], AlertProviders.catalog.select { |entry| entry[:secretFromProvider] }.pluck(:provider)
  end

  test "copy shown to people holds no em dashes or semicolons" do
    AlertProviders.catalog.flat_map { |entry| entry[:steps] }.each do |step|
      assert_no_match(/[—;]/, step)
    end
  end
end
