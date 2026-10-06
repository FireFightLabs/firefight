# A sweep reads services' settings only in memory. These check that none of a test's setting values, nor the passwords
# in them, reached a snapshot or anything a sweep writes.
module SettingValuesHelper
  def assert_no_setting_values(snapshot, *values)
    values = values.flatten.map(&:to_s).reject(&:empty?)
    assert values.any?, "name the values a sweep must not keep"
    written = [ ResourceMap::Use, ResourceMap::Endpoint, ResourceMap::Link, ResourceMap::Resource, ResourceMap::Change, IntegrationEnvironment ]
              .map { |model| model.all.to_a.to_json }
    [ snapshot.inspect, *written ].each do |text|
      values.each { |value| assert_not_includes text, value, "a setting's value was kept" }
    end
  end
end
