require "test_helper"

# CI loads the schema rather than running migrations, so two migrations sharing a version pass every test while a
# deploy that migrates refuses to start.
class MigrationVersionsTest < ActiveSupport::TestCase
  test "every migration has a version of its own" do
    versions = Dir[Rails.root.join("db/migrate/*.rb")].map { |path| File.basename(path)[/\A\d+/] }

    assert_equal [], versions.tally.select { |_version, count| count > 1 }.keys
  end
end
