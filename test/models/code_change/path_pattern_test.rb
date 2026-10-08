require "test_helper"

class CodeChange::PathPatternTest < ActiveSupport::TestCase
  def matches(pattern, *paths) = paths.each { |path| assert CodeChange::PathPattern.match?(pattern, path), "#{pattern} should cover #{path}" }

  def misses(pattern, *paths) = paths.each { |path| refute CodeChange::PathPattern.match?(pattern, path), "#{pattern} should not cover #{path}" }

  test "a folder holds everything under it, at any depth when it names one folder" do
    matches ".github/", ".github/workflows/release.yml", ".github/CODEOWNERS", "docs/.github/x"
    misses ".github/", ".github", ".githubrc", "src/github/x"
    matches "infra/prod/", "infra/prod/main.tf", "infra/prod/eu/vars.tf"
    misses "infra/prod/", "infra/production/main.tf", "old/infra/prod/main.tf"
  end

  test "a pattern with no slash matches a name at any depth, and one with a slash from the root" do
    matches "*.lock", "Gemfile.lock", "web/yarn.lock", "a/b/c/Cargo.lock"
    misses "*.lock", "lockfile", "Gemfile.lock.bak"
    matches "Dockerfile", "Dockerfile", "services/api/Dockerfile"
    matches "/Dockerfile", "Dockerfile"
    misses "/Dockerfile", "services/api/Dockerfile"
    matches "config/secrets.yml", "config/secrets.yml"
    misses "config/secrets.yml", "app/config/secrets.yml"
  end

  test "a double star spans folders, a star stays within a name and a question mark is one character" do
    matches "infra/prod/**", "infra/prod/main.tf", "infra/prod/eu/west/vars.tf"
    misses "infra/prod/**", "infra/production/main.tf"
    matches "**/secrets.yml", "secrets.yml", "config/secrets.yml", "a/b/secrets.yml"
    matches "db/*.sql", "db/schema.sql"
    misses "db/*.sql", "db/migrate/1.sql"
    matches "deploy/v?.yml", "deploy/v1.yml"
    misses "deploy/v?.yml", "deploy/v10.yml"
    matches "./.github/workflows/", ".github/workflows/ci.yml"
  end

  test "a pattern read differently from how it was meant is refused with why" do
    assert_nil CodeChange::PathPattern.refusal("infra/prod/**")
    assert_equal "!docs/ is an exception, and the list has none. List only the paths Halon may not change.", CodeChange::PathPattern.refusal("!docs/")
    assert_match "uses [ ], { } or \\", CodeChange::PathPattern.refusal("*.{lock,sum}")
    assert_match "uses [ ], { } or \\", CodeChange::PathPattern.refusal("src/[ab].rb")
    assert_equal "../secrets reaches outside the repository. Give a path inside it, such as infra/prod/", CodeChange::PathPattern.refusal("../secrets")
    assert_equal "/ names no file or folder. Give one, such as infra/prod/", CodeChange::PathPattern.refusal("/")
    assert_match "is longer than 200 characters", CodeChange::PathPattern.refusal("a" * 201)
  end
end
