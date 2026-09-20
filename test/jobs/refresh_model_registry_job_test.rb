require "test_helper"

class RefreshModelRegistryJobTest < ActiveSupport::TestCase
  test "the registry is pulled in and what it now knows is written down" do
    FirefightAi.expects(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    Rails.logger.expects(:info).with { |line| JSON.parse(line)["models"] == 1722 }

    RefreshModelRegistryJob.perform_now
  end

  test "a model this deployment runs on but cannot price is named, since its spend cap can never fire" do
    workspaces(:slack_workspace_one).ai_model_overrides.create!(purpose: AiPurpose::ANY, model: "priceless-one")
    FirefightAi.expects(:refresh_models!).returns(1722)
    FirefightAi.stubs(:priced?).returns(true)
    FirefightAi.stubs(:priced?).with("priceless-one").returns(false)
    Rails.logger.stubs(:info)
    Rails.logger.expects(:warn).with { |line| JSON.parse(line)["models"] == [ "priceless-one" ] }

    RefreshModelRegistryJob.perform_now
  end

  test "every environment refreshes the registry, since nothing else fills the table" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"))

    %w[development staging production].each do |environment|
      assert_equal "RefreshModelRegistryJob", schedule.dig(environment, "refresh_model_registry", "class")
    end
  end
end
