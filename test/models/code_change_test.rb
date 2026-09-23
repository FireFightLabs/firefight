require "test_helper"

class CodeChangeTest < ActiveSupport::TestCase
  test "a changed file is sorted by what kind of change it is, most likely to break production first" do
    {
      "db/migrate/20260924_add_index.rb" => CodeChange::KIND_MIGRATION,
      "config/database.yml" => CodeChange::KIND_CONFIG,
      "config/initializers/flipper.rb" => CodeChange::KIND_FEATURE_FLAG,
      "Gemfile.lock" => CodeChange::KIND_DEPENDENCY,
      "web/package.json" => CodeChange::KIND_DEPENDENCY,
      "infra/main.tf" => CodeChange::KIND_INFRASTRUCTURE,
      ".github/workflows/deploy.yml" => CodeChange::KIND_INFRASTRUCTURE,
      "app/models/pool.rb" => CodeChange::KIND_CODE,
      "test/models/pool_test.rb" => CodeChange::KIND_TEST,
      "README.md" => CodeChange::KIND_DOCS
    }.each { |path, kind| assert_equal kind, CodeChange.kind_for(path), path }
  end

  test "every kind is ordered and labelled" do
    assert_equal CodeChange::KINDS.sort, CodeChange::KIND_LABELS.keys.sort
  end
end
