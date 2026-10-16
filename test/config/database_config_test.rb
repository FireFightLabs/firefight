require "test_helper"

# Every round trip to the database costs milliseconds in production, so a deployed process keeps its connections, and
# the statements each one prepared, between requests.
class DatabaseConfigTest < ActiveSupport::TestCase
  DEPLOYED = %w[production staging].freeze
  DATABASES = %w[primary cache queue cable].freeze
  # PlanetScale may end a connection held for more than a day.
  LONGEST_LIFE = 24.hours

  test "a deployed process never closes a connection for sitting idle" do
    each_deployed_config do |config|
      assert_nil config.idle_timeout, "#{config.env_name} #{config.name} closes idle connections"
    end
  end

  test "a deployed connection is replaced well within a day and still kept alive while idle" do
    each_deployed_config do |config|
      assert_operator config.max_age, :<=, LONGEST_LIFE.to_i, "#{config.env_name} #{config.name} keeps a connection too long"
      assert_not_nil config.keepalive, "#{config.env_name} #{config.name} never pings an idle connection"
    end
  end

  test "a deployed process keeps prepared statements" do
    each_deployed_config do |config|
      assert_not_equal false, config.configuration_hash[:prepared_statements], "#{config.env_name} #{config.name} turns prepared statements off"
    end
  end

  private

  def each_deployed_config(&)
    configs = ActiveRecord::DatabaseConfigurations.new(deployed_yaml)
    DEPLOYED.each do |env|
      found = configs.configs_for(env_name: env)
      assert_equal DATABASES.sort, found.map(&:name).sort, "#{env} names every database"
      found.each(&)
    end
  end

  def deployed_yaml
    YAML.safe_load(ERB.new(Rails.root.join("config/database.yml").read).result, aliases: true)
  end
end
