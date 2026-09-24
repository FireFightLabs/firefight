# What a changed file is, read from its path, so the kinds of change that most often break production are looked at first.
# Nothing here knows a code host, so any adapter that lists changed files can use it.
module CodeChange
  KIND_MIGRATION = "migration".freeze
  KIND_CONFIG = "config".freeze
  KIND_FEATURE_FLAG = "feature_flag".freeze
  KIND_DEPENDENCY = "dependency".freeze
  KIND_INFRASTRUCTURE = "infrastructure".freeze
  KIND_CODE = "code".freeze
  KIND_TEST = "test".freeze
  KIND_DOCS = "docs".freeze

  # Most likely to cause an incident first.
  KINDS = [ KIND_MIGRATION, KIND_CONFIG, KIND_FEATURE_FLAG, KIND_DEPENDENCY, KIND_INFRASTRUCTURE, KIND_CODE, KIND_TEST, KIND_DOCS ].freeze

  KIND_LABELS = {
    KIND_MIGRATION => "Database migrations", KIND_CONFIG => "Configuration", KIND_FEATURE_FLAG => "Feature flags",
    KIND_DEPENDENCY => "Dependencies", KIND_INFRASTRUCTURE => "Infrastructure", KIND_CODE => "Application code",
    KIND_TEST => "Tests", KIND_DOCS => "Documentation"
  }.freeze

  # Checked in order, so a migration under config/ still reads as a migration.
  PATTERNS = [
    [ KIND_MIGRATION, %r{(\A|/)(db/migrate|migrations?|alembic/versions)/|\A(db/)?(schema\.rb|structure\.sql)\z|\.sql\z}i ],
    [ KIND_FEATURE_FLAG, %r{(\A|/)(feature[_-]?flags?|flags|flipper|launchdarkly|unleash)(/|\.|\z)}i ],
    [ KIND_DEPENDENCY, %r{(\A|/)(Gemfile(\.lock)?|package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|go\.(mod|sum)|requirements[^/]*\.txt|Pipfile(\.lock)?|poetry\.lock|pyproject\.toml|Cargo\.(toml|lock)|composer\.(json|lock)|mix\.(exs|lock))\z}i ],
    [ KIND_INFRASTRUCTURE, %r{\.tf(vars)?\z|(\A|/)(Chart\.yaml|values[^/]*\.ya?ml|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|compose\.ya?ml|Procfile)\z|(\A|/)(k8s|kubernetes|helm|charts|deploy|terraform|infra|\.github/workflows)/}i ],
    [ KIND_TEST, %r{(\A|/)(test|tests|spec|specs|__tests__)/|_(test|spec)\.[a-z]+\z|\.(test|spec)\.[a-z]+\z}i ],
    [ KIND_DOCS, %r{\.(md|mdx|rst|txt)\z|(\A|/)docs?/}i ],
    [ KIND_CONFIG, %r{(\A|/)(config|settings|conf)/|\.(ya?ml|toml|ini|json|env\.example)\z}i ]
  ].freeze

  def self.kind_for(path)
    PATTERNS.find { |_kind, pattern| path.to_s.match?(pattern) }&.first || KIND_CODE
  end

  # "owner/name", however it was written: a bare owner/name, or a web or clone address on any code host. Nil for anything else.
  def self.repository_name(text)
    path = text.to_s.strip.sub(%r{\A(?:https?://|git@)[^/:]+[/:]}, "").delete_suffix(".git").delete_suffix("/")
    path if path.match?(%r{\A[\w.\-]+/[\w.\-]+\z})
  end
end
