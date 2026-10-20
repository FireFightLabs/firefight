require "test_helper"

class RefreshModelRegistryJobTest < ActiveSupport::TestCase
  test "the registry is pulled in and what it now knows is written down" do
    FirefightAi.expects(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
    Rails.logger.expects(:info).with { |line| JSON.parse(line)["models"] == 1722 }

    RefreshModelRegistryJob.perform_now
  end

  test "a model this deployment runs on but cannot price is named, since its spend cap can never fire" do
    workspaces(:slack_workspace_one).ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "priceless-one")
    FirefightAi.expects(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    FirefightAi.stubs(:priced?).with("priceless-one").returns(false)
    FirefightAi.stubs(:context_window).returns(200_000)
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.expects(:warn).with { |line| JSON.parse(line)["models"] == [ "priceless-one" ] }

    RefreshModelRegistryJob.perform_now
  end

  test "a model the agent would run on with no known window is named, since it cannot run until it has one" do
    FirefightAi.expects(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    FirefightAi.stubs(:context_window).returns(nil)
    Rails.logger.stubs(:info)
    Rails.logger.stubs(:warn)
    Rails.logger.expects(:warn).with { |line| JSON.parse(line)["event"] == "ai.models_without_context_window" }

    RefreshModelRegistryJob.perform_now
  end

  test "a provider's off-peak dates running out are named from 45 days before, so next year's are added in time" do
    FirefightAi.stubs(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
    Rails.logger.stubs(:info)
    warned = []
    Rails.logger.stubs(:warn).with { |line| warned << JSON.parse(line) }

    travel_to(Time.utc(2026, 11, 1)) { RefreshModelRegistryJob.perform_now }
    assert_empty warned, "the year's dates are listed and its end is far enough away"

    travel_to(Time.utc(2026, 11, 20)) { RefreshModelRegistryJob.perform_now }
    assert_equal [ { "event" => "ai.peak_pricing_dates_ending", "providers" => [ { "provider" => "deepseek", "known_through" => "2026-12-31" } ] } ], warned
  end

  test "every environment refreshes the registry, since nothing else fills the table" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"))

    %w[development staging production].each do |environment|
      assert_equal "RefreshModelRegistryJob", schedule.dig(environment, "refresh_model_registry", "class")
    end
  end
end
